%% @author Northscale <info@northscale.com>
%% @copyright 2010 NorthScale, Inc.
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
-module(ns_server).

-behavior(application).

-export([start/2, stop/1]).

-include("ns_common.hrl").
-include_lib("ale/include/ale.hrl").

log_pending() ->
    receive
        done ->
            ok;
        {LogLevel, Fmt, Args} ->
            ?LOG(LogLevel, Fmt, Args),
            log_pending()
    end.

start(_Type, _Args) ->
    setup_static_config(),
    init_logging(),

    %% To initialize logging static config must be setup thus this weird
    %% machinery is required to log messages from setup_static_config().
    self() ! done,
    log_pending(),

    ns_server_cluster_sup:start_link().

get_config_path() ->
    case application:get_env(ns_server, config_path) of
        {ok, V} -> V;
        _ ->
             erlang:error("config_path parameter for ns_server application is missing!")
    end.

setup_static_config() ->
    Terms = case file:consult(get_config_path()) of
                {ok, T} when is_list(T) ->
                    T;
                _ ->
                    erlang:error("failed to read static config: " ++ get_config_path() ++ ". It must be readable file with list of pairs~n")
            end,
    self() ! {info, "Static config terms:~n~p", [Terms]},
    lists:foreach(fun ({K,V}) ->
                          case application:get_env(ns_server, K) of
                              undefined ->
                                  application:set_env(ns_server, K, V);
                              _ ->
                                  self() ! {warn,
                                            "not overriding parameter ~p, which is given from command line",
                                            [K]}
                          end
                  end, Terms).

get_loglevel(LoggerName) ->
    {ok, DefaultLogLevel} = application:get_env(loglevel_default),
    LoggerNameStr = atom_to_list(LoggerName),
    Key = list_to_atom("loglevel_" ++ LoggerNameStr),
    misc:get_env_default(Key, DefaultLogLevel).

init_logging() ->
    StdLoggers = [?ERROR_LOGGER],
    AllLoggers = StdLoggers ++ ?LOGGERS,

    {ok, Dir} = application:get_env(error_logger_mf_dir),
    {ok, MaxB} = application:get_env(error_logger_mf_maxbytes),
    {ok, MaxF} = application:get_env(error_logger_mf_maxfiles),

    DefaultLogPath = filename:join(Dir, ?DEFAULT_LOG_FILENAME),
    ErrorLogPath = filename:join(Dir, ?ERRORS_LOG_FILENAME),
    DebugLogPath = filename:join(Dir, ?DEBUG_LOG_FILENAME),

    DiskSinkParams = [{size, {MaxB, MaxF}}],

    ok = ale:start_sink(disk_default,
                        ale_disk_sink, [DefaultLogPath, DiskSinkParams]),
    ok = ale:start_sink(disk_error,
                        ale_disk_sink, [ErrorLogPath, DiskSinkParams]),
    ok = ale:start_sink(disk_debug,
                        ale_disk_sink, [DebugLogPath, DiskSinkParams]),
    ok = ale:start_sink(ns_log, raw, ns_log_sink, []),

    lists:foreach(
      fun (Logger) ->
              ok = ale:start_logger(Logger, debug)
      end, ?LOGGERS),

    lists:foreach(
      fun (Logger) ->
              ok = ale:set_loglevel(Logger, debug)
      end,
      StdLoggers),

    lists:foreach(
      fun (Logger) ->
              LogLevel = get_loglevel(Logger),
              ok = ale:add_sink(Logger, disk_default, LogLevel),

              ok = ale:add_sink(Logger, disk_error, error),
              ok = ale:add_sink(Logger, disk_debug, debug)
      end, AllLoggers),

    ok = ale:add_sink(?USER_LOGGER, ns_log, info),
    ok = ale:add_sink(?MENELAUS_LOGGER, ns_log, info),
    ok = ale:add_sink(?CLUSTER_LOGGER, ns_log, info),
    ok = ale:add_sink(?REBALANCE_LOGGER, ns_log, error),

    case misc:get_env_default(dont_suppress_stderr_logger, false) of
        true ->
            ok = ale:start_sink(stderr, ale_stderr_sink, []),

            lists:foreach(
              fun (Logger) ->
                      %% usually used only in dev environment so it makes
                      %% sense to put all the messages here
                      ok = ale:add_sink(Logger, stderr, debug)
              end, AllLoggers);
        false ->
            ok
    end,
    ale:sync_changes(infinity),
    ale:info(?NS_SERVER_LOGGER, "Started & configured logging").

stop(_State) ->
    ok.
