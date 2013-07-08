%% @author Northscale <info@northscale.com>
%% @copyright 2009 NorthScale, Inc.
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
%% Distributed erlang configuration and management
%%
-module(dist_manager).

-behaviour(gen_server).

-include("ns_common.hrl").

-export([start_link/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([adjust_my_address/1, read_address_config/0, save_address_config/1, ip_config_path/0]).

-record(state, {self_started, my_ip}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

ip_config_path() ->
    path_config:component_path(data, "ip").

strip_full(String) ->
    String2 = string:strip(String),
    String3 = string:strip(String2, both, $\n),
    String4 = string:strip(String3, both, $\r),
    case String4 =:= String of
        true ->
            String4;
        _ ->
            strip_full(String4)
    end.

read_address_config() ->
    Path = ip_config_path(),
    ?log_info("reading ip config from ~p", [Path]),
    case file:read_file(Path) of
        {ok, BinaryContents} ->
            AddrString = strip_full(binary_to_list(BinaryContents)),
            case inet:getaddr(AddrString, inet) of
                {error, Errno1} ->
                    ?log_error("Got error:~p. Ignoring bad address:~p",
                               [Errno1, AddrString]),
                    undefined;
                {ok, IpAddr} ->
                    case gen_tcp:listen(0, [inet, {ip, IpAddr}]) of
                        {error, Errno2} ->
                            ?log_error("Got error:~p. Cannot listen on configured address:~s",
                                       [Errno2, AddrString]),
                            undefined;
                        {ok, Socket} ->
                            gen_tcp:close(Socket),
                            AddrString
                    end
            end;
        {error, enoent} ->
            ?log_info("ip config not found. Looks like we're brand new node"),
            undefined;
        _ -> undefined
    end.

save_address_config(State) ->
    Path = ip_config_path(),
    ?log_info("saving ip config to ~p", [Path]),
    misc:atomic_write_file(Path, State#state.my_ip).

save_node(NodeName, Path) ->
    ?log_info("saving node to ~p", [Path]),
    misc:atomic_write_file(Path, NodeName ++ "\n").

save_node(NodeName) ->
    case application:get_env(nodefile) of
        {ok, NodeFile} -> save_node(NodeName, NodeFile);
        X -> X
    end.

init([]) ->
    InitialAddr = case read_address_config() of
                      undefined -> "127.0.0.1";
                      X -> X
                  end,
    {ok, bringup(InitialAddr)}.

%% There are only two valid cases here:
%% 1. Successfully started
decode_status({ok, _Pid}) ->
    true;
%% 2. Already initialized (via -name or -sname)
decode_status({error, {{already_started, _Pid}, _Stack}}) ->
    false.

adjust_my_address(MyIP) ->
    gen_server:call(?MODULE, {adjust_my_address, MyIP}).

%% Call net_kernel:start(Opts) but ignore {error, duplicate_name} error for
%% several times. Then give up if error is still returned. This weird logic is
%% needed because epmd daemon unregisters old node name when socket (that was
%% used to register this name) is closed. This is, of course, what happens
%% when net_kernel:stop() is called. But it seems that there's no guarantee
%% that subsequent register request will be handled after old node name has
%% been unregistered. And because ns_1@127.0.0.1 and ns_1@10.1.3.75 are
%% actually conflicting names we can hit this duplicate_name error.
do_net_kernel_start(Opts) ->
    do_net_kernel_start(Opts, 5).

do_net_kernel_start(Opts, Tries) when is_integer(Tries) ->
    case net_kernel:start(Opts) of
        {error, duplicate_name} ->
            case Tries of
                0 ->
                    {error, duplicate_name};
                _ ->
                    ?log_warning("Failed to bring up net_kernel because of "
                                 "duplicate name. Will try ~b more times",
                                 [Tries]),
                    timer:sleep(500),
                    do_net_kernel_start(Opts, Tries - 1)
            end;
        Other ->
            Other
    end.

%% Bring up distributed erlang.
bringup(MyIP) ->
    ShortName = misc:get_env_default(short_name, "ns_1"),
    MyNodeNameStr = ShortName ++ "@" ++ MyIP,
    MyNodeName = list_to_atom(MyNodeNameStr),

    ?log_info("Attempting to bring up net_kernel with name ~p", [MyNodeName]),
    Rv = decode_status(do_net_kernel_start([MyNodeName, longnames])),
    net_kernel:set_net_ticktime(misc:get_env_default(set_net_ticktime, 60)),

    %% Rv can be false in case -name has been passed to erl but we still need
    %% to save the node name to be able to shutdown the server gracefully.
    ActualNodeName = erlang:atom_to_list(node()),
    RN = save_node(ActualNodeName),
    ?log_debug("Attempted to save node name to disk: ~p", [RN]),

    #state{self_started = Rv, my_ip = MyIP}.

%% Tear down distributed erlang.
teardown() ->
    ok = net_kernel:stop().

handle_call({adjust_my_address, MyIP}, _From,
            #state{self_started = true, my_ip = MyOldIP} = State) ->
    case MyIP =:= MyOldIP of
        true -> {reply, nothing, State};
        false -> Cookie = erlang:get_cookie(),
                 teardown(),
                 ?log_info("Adjusted IP to ~p", [MyIP]),
                 NewState = bringup(MyIP),
                 if
                     NewState#state.self_started ->
                         ?log_info("Re-setting cookie ~p", [{Cookie, node()}]),
                         erlang:set_cookie(node(), Cookie);
                     true -> ok
                 end,

                 RV = save_address_config(NewState),
                 ?log_debug("save_address_config: ~p", [RV]),
                 {reply, net_restarted, NewState}
    end;
handle_call({adjust_my_address, _}, _From,
            #state{self_started = false} = State) ->
    {reply, nothing, State};
handle_call(_Request, _From, State) ->
    {reply, unhandled, State}.

handle_cast(_, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
