%% @author Couchbase, Inc <info@couchbase.com>
%% @copyright 2011 Couchbase, Inc.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%      http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

%% @doc Does auto failover nodes that are down.
%% It works like that: You specify a certain time interval a node
%% must be down, before it will be auto-failovered. There's also a
%% maximum number of nodes that may be auto-failovered. Whenever a node
%% gets auto-failovered a counter is increased by one. Once the counter
%% has reached the maximum number of nodes that may be auto-failovered
%% the user will only get a notification that there was a node that would
%% have been auto-failovered if the maximum wouldn't have been reached.

-module(auto_failover).

-include_lib("eunit/include/eunit.hrl").

-behaviour(gen_server).

-include("ns_common.hrl").
-include("ns_heart.hrl").

%% API
-export([start_link/0, enable/2, disable/0, reset_count/0]).
%% For email alert notificatons
-export([alert_key/1, alert_keys/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, {global, ?MODULE}).
%% @doc Fired when a node was auto-failovered.
-define(EVENT_NODE_AUTO_FAILOVERED, 1).
%% @doc Fired when the maximum number of nodes that can be auto-failovered
%% was reached (and thus the auto-failover was disabled).
-define(EVENT_MAX_REACHED, 2).
%% @doc Fired when another node is down while we were trying to failover
%% a node
-define(EVENT_OTHER_NODES_DOWN, 3).
%% @doc Fired when the cluster gets to small to do a safe auto-failover
-define(EVENT_CLUSTER_TOO_SMALL, 4).

%% @doc The time a stats request to a bucket may take (in milliseconds)
-define(STATS_TIMEOUT, 2000).

-record(state, {
          auto_failover_logic_state,
          % Reference to the ns_tick_event. If it is nil, auto-failover is
          % disabled.
          tick_ref=nil :: nil | timer:tref(),
          % Time a node needs to be down until it is automatically failovered
          timeout=nil :: nil | integer(),
          % Counts the number of nodes that were already auto-failovered
          count=0 :: non_neg_integer()
         }).

%%
%% API
%%

start_link() ->
    misc:start_singleton(gen_server, ?MODULE, [], []).

%% @doc Enable auto-failover. Failover after a certain time (in seconds),
%% Returns an error (and reason) if it couldn't be enabled, e.g. because
%% not all nodes in the cluster were healthy.
%% `Timeout` is the number of seconds a node must be down before it will be
%% automatically failovered
%% `Max` is the maximum number of nodes that can will be automatically
%% failovered
-spec enable(Timeout::integer(), Max::integer()) -> ok.
enable(Timeout, Max) ->
    1 = Max,
    gen_server:call(?SERVER, {enable_auto_failover, Timeout, Max}).

%% @doc Disable auto-failover
-spec disable() -> ok.
disable() ->
    gen_server:call(?SERVER, disable_auto_failover).

%% @doc Reset the number of nodes that were auto-failovered to zero
-spec reset_count() -> ok.
reset_count() ->
    gen_server:call(?SERVER, reset_auto_failover_count).

-spec alert_key(Code::integer()) -> atom().
alert_key(?EVENT_NODE_AUTO_FAILOVERED) -> auto_failover_node;
alert_key(?EVENT_MAX_REACHED) -> auto_failover_maximum_reached;
alert_key(?EVENT_OTHER_NODES_DOWN) -> auto_failover_other_nodes_down;
alert_key(?EVENT_CLUSTER_TOO_SMALL) -> auto_failover_cluster_too_small;
alert_key(_) -> all.

%% @doc Returns a list of all alerts that might send out an email notification.
-spec alert_keys() -> [atom()].
alert_keys() ->
    [auto_failover_node,
     auto_failover_maximum_reached,
     auto_failover_other_nodes_down,
     auto_failover_cluster_too_small].

%%
%% gen_server callbacks
%%

init([]) ->
    {value, Config} = ns_config:search(ns_config:get(), auto_failover_cfg),
    ?log_debug("init auto_failover.", []),
    Timeout = proplists:get_value(timeout, Config),
    Count = proplists:get_value(count, Config),
    State = #state{timeout=Timeout,
                   count=Count,
                   auto_failover_logic_state = undefined},
    case proplists:get_value(enabled, Config) of
        true ->
            {reply, ok, State2} = handle_call(
                                    {enable_auto_failover, Timeout, 1},
                                    self(), State),
            {ok, State2};
        false ->
            {ok, State}
    end.

init_logic_state(Timeout) ->
    DownThreshold = (Timeout * 1000 + ?HEART_BEAT_PERIOD - 1) div ?HEART_BEAT_PERIOD,
    auto_failover_logic:init_state(DownThreshold).

%% @doc Auto-failover isn't enabled yet (tick_ref isn't set).
handle_call({enable_auto_failover, Timeout, Max}, _From,
            #state{tick_ref=nil}=State) ->
    1 = Max,
    ale:info(?USER_LOGGER, "Enabled auto-failover with timeout ~p", [Timeout]),
    {ok, Ref} = timer:send_interval(?HEART_BEAT_PERIOD, tick),
    State2 = State#state{tick_ref=Ref, timeout=Timeout,
                         auto_failover_logic_state=init_logic_state(Timeout)},
    make_state_persistent(State2),
    {reply, ok, State2};
%% @doc Auto-failover is already enabled, just update the settings.
handle_call({enable_auto_failover, Timeout, Max}, _From, State) ->
    ?log_debug("updating auto-failover settings: ~p", [State]),
    1 = Max,
    ale:info(?USER_LOGGER, "Updating auto-failover timeout to ~p", [Timeout]),
    State2 = State#state{timeout=Timeout,
                         auto_failover_logic_state = init_logic_state(Timeout)},
    make_state_persistent(State2),
    {reply, ok, State2};

%% @doc Auto-failover is already disabled, so we don't do anything
handle_call(disable_auto_failover, _From, #state{tick_ref=nil}=State) ->
    {reply, ok, State};
%% @doc Auto-failover is enabled, disable it
handle_call(disable_auto_failover, _From, #state{tick_ref=Ref}=State) ->
    ?log_debug("disable_auto_failover: ~p", [State]),
    {ok, cancel} = timer:cancel(Ref),
    State2 = State#state{tick_ref=nil, auto_failover_logic_state = undefined},
    make_state_persistent(State2),
    {reply, ok, State2};

handle_call(reset_auto_failover_count, _From, State) ->
    ?log_debug("reset auto_failover count: ~p", [State]),
    State2 = State#state{count=0,
                         auto_failover_logic_state = init_logic_state(State#state.timeout)},
    make_state_persistent(State2),
    {reply, ok, State2};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @doc Check if nodes should/could be auto-failovered on every tick
handle_info(tick, State0) ->
    Config = ns_config:get(),

    %% Reread autofailover count from config just in case. This value can be
    %% different, for instance, if due to network issues we get disconnected
    %% from the part of the cluster. This part of the cluster will elect new
    %% master node. Now say this new master node autofailovers some other
    %% node. Then if network issues disappear, we will connect back to the
    %% rest of the cluster. And say we win the battle over mastership
    %% again. In this case our failover count will still be zero which is
    %% incorrect.
    {value, AutoFailoverConfig} = ns_config:search(Config, auto_failover_cfg),
    AutoFailoverCount = proplists:get_value(count, AutoFailoverConfig),
    true = is_integer(AutoFailoverCount),

    State = State0#state{count=AutoFailoverCount},

    NonPendingNodes = lists:sort(ns_cluster_membership:active_nodes(Config)),
    CurrentlyDown = actual_down_nodes(NonPendingNodes, Config),
    RebalanceRunning = case ns_config:search(rebalance_status) of
                           {value, running} -> true;
                           _ -> false
                       end,
    {Actions, LogicState} =
        auto_failover_logic:process_frame(NonPendingNodes,
                                          CurrentlyDown,
                                          State#state.auto_failover_logic_state,
                                          RebalanceRunning),
    NewState =
        lists:foldl(
          fun ({mail_too_small, Node}, S) ->
                  ?user_log(?EVENT_CLUSTER_TOO_SMALL,
                            "Could not auto-failover node (~p). "
                            "Cluster was too small, you need at least 2 other nodes.~n",
                            [Node]),
                  S;
              ({rebalance_prevented_failover, Node}, S) ->
                  ale:info(?USER_LOGGER,
                           "Could not automatically failover node ~p because I think rebalance is running",
                           [Node]),
                  S;
              ({_, Node}, #state{count=1} = S) ->
                  ?user_log(?EVENT_MAX_REACHED,
                            "Could not auto-failover more nodes (~p). "
                            "Maximum number of nodes that will be "
                            "automatically failovered (1) is reached.~n",
                            [Node]),
                  S;
              ({mail_down_warning, Node}, S) ->
                  ?user_log(?EVENT_OTHER_NODES_DOWN,
                            "Could not auto-failover node (~p). "
                            "There was at least another node down.~n",
                            [Node]),
                  S;
              ({failover, Node}, S) ->
                  ns_cluster_membership:failover(Node),
                  ?user_log(?EVENT_NODE_AUTO_FAILOVERED,
                            "Node (~p) was automatically failovered.~n~p",
                            [Node, ns_doctor:get_node(Node)]),
                  S#state{count = S#state.count+1}
          end, State#state{auto_failover_logic_state = LogicState}, Actions),
    if
        NewState#state.count =/= State#state.count ->
            make_state_persistent(NewState);
        true -> ok
    end,
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%
%% Internal functions
%%

%% @doc Returns a list of nodes that should be active, but are not running.
-spec actual_down_nodes([atom()], [{atom(), term()}]) -> [atom()].
actual_down_nodes(NonPendingNodes, Config) ->
    % Get all buckets
    BucketConfigs = ns_bucket:get_buckets(Config),
    NodesDict = ns_doctor:get_nodes(),
    actual_down_nodes_inner(NonPendingNodes, BucketConfigs, NodesDict, erlang:now()).

actual_down_nodes_inner(NonPendingNodes, BucketConfigs, NodesDict, Now) ->
    BucketsServers = [{Name, lists:sort(proplists:get_value(servers, BC, []))}
                      || {Name, BC} <- BucketConfigs],

    lists:filter(
      fun (Node) ->
              case dict:find(Node, NodesDict) of
                  {ok, Info} ->
                      case proplists:get_value(last_heard, Info) of
                          T -> timer:now_diff(Now, T) > (?HEART_BEAT_PERIOD + ?STATS_TIMEOUT) * 1000
                      end orelse
                          begin
                              Ready = proplists:get_value(ready_buckets, Info, []),
                              ExpectedReady = [Name || {Name, Servers} <- BucketsServers,
                                                       ordsets:is_element(Node, Servers)],
                              (ExpectedReady -- Ready) =/= []
                          end;
                  error ->
                      true
              end
      end, NonPendingNodes).

actual_down_nodes_inner_test() ->
    PList0 = [{a, ["bucket1", "bucket2"]},
              {b, ["bucket1"]},
              {c, []}],
    NodesDict = dict:from_list([{N, [{ready_buckets, B},
                                     {last_heard, {0, 0, 0}}]}
                                || {N, B} <- PList0]),
    R = fun (Nodes, Buckets) ->
                actual_down_nodes_inner(Nodes, Buckets, NodesDict, {0, 0, 0})
        end,
    ?assertEqual([], R([a, b, c], [])),
    ?assertEqual([], R([a, b, c],
                       [{"bucket1", [{servers, [a]}]}])),
    ?assertEqual([], R([a, b, c],
                       [{"bucket1", [{servers, [a, b]}]}])),
    %% this also tests too "old" hearbeats a bit
    ?assertEqual([a,b,c],
                 actual_down_nodes_inner([a,b,c],
                                         [{"bucket1", [{servers, [a, b]}]}],
                                         NodesDict, {16#100000000, 0, 0})),
    ?assertEqual([c], R([a, b, c],
                        [{"bucket1", [{servers, [a, b, c]}]}])),
    ?assertEqual([b, c], R([a, b, c],
                           [{"bucket1", [{servers, [a, b, c]}]},
                            {"bucket2", [{servers, [a, b, c]}]}])),
    ?assertEqual([b, c], R([a, b, c],
                           [{"bucket2", [{servers, [a, b, c]}]}])),
    ?assertEqual([a, b, c], R([a, b, c],
                              [{"bucket3", [{servers, [a]}]},
                               {"bucket2", [{servers, [a, b, c]}]}])),
    ok.

%% @doc Save the current state in ns_config
-spec make_state_persistent(State::#state{}) -> ok.
make_state_persistent(State) ->
    Enabled = case State#state.tick_ref of
        nil -> false;
        _ -> true
    end,
    ns_config:set(auto_failover_cfg,
                  [{enabled, Enabled},
                   {timeout, State#state.timeout},
                   {count, State#state.count}]).
