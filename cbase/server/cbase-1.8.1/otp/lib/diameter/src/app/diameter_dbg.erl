%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2010-2011. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

-module(diameter_dbg).

-export([table/1,
         tables/0,
         fields/1,
         help/0,
         modules/0,
         versions/0,
         version_info/0,
         compiled/0,
         procs/0,
         latest/0,
         nl/0,
         log/4]).

-export([diameter_config/0,
         diameter_peer/0,
         diameter_reg/0,
         diameter_request/0,
         diameter_sequence/0,
         diameter_service/0,
         diameter_stats/0]).

-export([pp/1,
         subscriptions/0,
         children/0]).

%% Trace help.
-export([tracer/0, tracer/1,
         p/0, p/1,
         stop/0,
         tpl/1,
         tp/1]).

-include_lib("diameter/include/diameter.hrl").
-include("diameter_internal.hrl").


-define(INFO,  diameter_info).
-define(SEP(), ?INFO:sep()).

-define(LOCAL, [diameter_config,
                diameter_peer,
                diameter_reg,
                diameter_request,
                diameter_sequence,
                diameter_service,
                diameter_stats]).

-define(VALUES(Rec), tl(tuple_to_list(Rec))).

%%% ----------------------------------------------------------
%%% # log/4
%%%
%%% Called to have something to trace on for happenings of interest.
%%% ----------------------------------------------------------

log(_Slogan, _Mod, _Line, _Details) ->
    ok.

%%% ----------------------------------------------------------
%%% # help()
%%% ----------------------------------------------------------

help() ->
    ?INFO:usage(usage()).

usage() ->
    not_yet_implemented.

%%% ----------------------------------------------------------
%%% # table(TableName)
%%%
%%% Input:  TableName = diameter table containing record entries.
%%%
%%% Output: Count | undefined
%%% ----------------------------------------------------------

table(T)
  when (T == diameter_peer) orelse (T == diameter_reg) ->
    ?INFO:format(collect(T), fields(T), fun ?INFO:split/2);

table(diameter_service = T) ->
    Fs = [name, started] ++ fields(T) ++ [peerT,
                                          connT,
                                          share_peers,
                                          use_shared_peers,
                                          shared_peers,
                                          local_peers,
                                          monitor],
    ?INFO:format(T,
                 fun(R) ->
                         [I,N,S|Vs] = ?VALUES(R),
                         {Fs, [N,I] ++ ?VALUES(S) ++ Vs}
                 end,
                 fun ?INFO:split/2);

table(Table)
  when is_atom(Table) ->
    case fields(Table) of
        undefined = No ->
            No;
        Fields ->
            ?INFO:format(Table, Fields, fun ?INFO:split/2)
    end.

%%% ----------------------------------------------------------
%%% # TableName()
%%% ----------------------------------------------------------

-define(TABLE(Name), Name() -> table(Name)).

?TABLE(diameter_config).
?TABLE(diameter_peer).
?TABLE(diameter_reg).
?TABLE(diameter_request).
?TABLE(diameter_sequence).
?TABLE(diameter_service).
?TABLE(diameter_stats).

%%% ----------------------------------------------------------
%%% # tables()
%%%
%%% Output: Number of records output.
%%%
%%% Description: Pretty-print records in diameter tables from all nodes.
%%% ----------------------------------------------------------

tables() ->
    format_all(fun ?INFO:split/3).

format_all(SplitFun) ->
    ?INFO:format(field(?LOCAL), SplitFun, fun collect/1).

field(Tables) ->
    lists:map(fun(T) -> {T, fields(T)} end, lists:sort(Tables)).

%%% ----------------------------------------------------------
%%% # modules()
%%% ----------------------------------------------------------

modules() ->
    Path = filename:join([appdir(), atom_to_list(?APPLICATION) ++ ".app"]),
    {ok, [{application, ?APPLICATION, Attrs}]} = file:consult(Path),
    {modules, Mods} = lists:keyfind(modules, 1, Attrs),
    Mods.

appdir() ->
    [_|_] = code:lib_dir(?APPLICATION, ebin).

%%% ----------------------------------------------------------
%%% # versions()
%%% ----------------------------------------------------------

versions() ->
    ?INFO:versions(modules()).

%%% ----------------------------------------------------------
%%% # versions()
%%% ----------------------------------------------------------

version_info() ->
    ?INFO:version_info(modules()).

%%% ----------------------------------------------------------
%%% # compiled()
%%% ----------------------------------------------------------

compiled() ->
    ?INFO:compiled(modules()).

%%% ----------------------------------------------------------
%%% procs()
%%% ----------------------------------------------------------

procs() ->
    ?INFO:procs(?APPLICATION).

%%% ----------------------------------------------------------
%%% # latest()
%%% ----------------------------------------------------------

latest() ->
    ?INFO:latest(modules()).

%%% ----------------------------------------------------------
%%% # nl()
%%% ----------------------------------------------------------

nl() ->
    lists:foreach(fun(M) -> abcast = c:nl(M) end, modules()).

%%% ----------------------------------------------------------
%%% # pp(Bin)
%%%
%%% Description: Pretty-print a message binary.
%%% ----------------------------------------------------------

%% Network byte order = big endian.

pp(<<Version:8, MsgLength:24,
     Rbit:1, Pbit:1, Ebit:1, Tbit:1, Reserved:4, CmdCode:24,
     ApplId:32,
     HbHid:32,
     E2Eid:32,
     AVPs/binary>>) ->
    ?SEP(),
    ppp(["Version",
         "Message length",
         "[Actual length]",
         "R(equest)",
         "P(roxiable)",
         "E(rror)",
         "T(Potential retrans)",
         "Reserved bits",
         "Command code",
         "Application id",
         "Hop by hop id",
         "End to end id"],
        [Version, MsgLength, size(AVPs) + 20,
         Rbit, Pbit, Ebit, Tbit, Reserved,
         CmdCode,
         ApplId,
         HbHid,
         E2Eid]),
    N = avp_loop({AVPs, MsgLength - 20}, 0),
    ?SEP(),
    N;

pp(<<_Version:8, MsgLength:24, _/binary>> = Bin) ->
    {bad_message_length, MsgLength, size(Bin)};

pp(Bin)
  when is_binary(Bin) ->
    {truncated_binary, size(Bin)};

pp(_) ->
    not_binary.

%% avp_loop/2

avp_loop({Bin, Size}, N) ->
    avp_loop(avp(Bin, Size), N+1);
avp_loop(ok, N) ->
    N;
avp_loop([_E, _Rest] = L, N) ->
    io:format("! ~s: ~p~n", L),
    N;
avp_loop([E, Rest, Fmt | Values], N)
  when is_binary(Rest) ->
    io:format("! ~s (" ++ Fmt ++ "): ~p~n", [E|Values] ++ [Rest]),
    N.

%% avp/2

avp(<<>>, 0) ->
    ok;
avp(<<Code:32, Flags:1/binary, Length:24, Rest/binary>>,
    Size) ->
    avp(Code, Flags, Length, Rest, Size);
avp(Bin, _) ->
    ["truncated AVP header", Bin].

%% avp/5

avp(Code, Flags, Length, Rest, Size) ->
    <<V:1, M:1, P:1, Res:5>>
        = Flags,
    b(),
    ppp(["AVP Code",
         "V(endor)",
         "M(andatory)",
         "P(Security)",
         "R(eserved)",
         "Length"],
        [Code, V, M, P, Res, Length]),
    avp(V, Rest, Length - 8, Size - 8).

%% avp/4

avp(1, <<V:32, Data/binary>>, Length, Size) ->
    ppp({"Vendor-ID", V}),
    data(Data, Length - 4, Size - 4);
avp(1, Bin, _, _) ->
    ["truncated Vendor-ID", Bin];
avp(0, Data, Length, Size) ->
    data(Data, Length, Size).

data(Bin, Length, Size)
  when size(Bin) >= Length ->
    <<AVP:Length/binary, Rest/binary>> = Bin,
    ppp({"Data", AVP}),
    unpad(Rest, Size - Length, Length rem 4);

data(Bin, _, _) ->
    ["truncated AVP data", Bin].

%% Remove padding bytes up to the next word boundary.
unpad(Bin, Size, 0) ->
    {Bin, Size};
unpad(Bin, Size, N) ->
    un(Bin, Size, 4 - N).

un(Bin, Size, N)
  when size(Bin) >= N ->
    ppp({"Padding bytes", N}),
    <<Pad:N/binary, Rest/binary>> = Bin,
    Bits = N*8,
    case Pad of
        <<0:Bits>> ->
            {Rest, Size - N};
        _ ->
            ["non-zero padding", Bin, "~p", N]
    end;

un(Bin, _, _) ->
    ["truncated padding", Bin].

b() ->
    io:format("#~n").

ppp(Fields, Values) ->
    lists:foreach(fun ppp/1, lists:zip(Fields, Values)).

ppp({Field, Value}) ->
    io:format(": ~-22s : ~p~n", [Field, Value]).

%%% ----------------------------------------------------------
%%% # subscriptions()
%%%
%%% Output: list of {SvcName, Pid}
%%% ----------------------------------------------------------

subscriptions() ->
    diameter_service:subscriptions().

%%% ----------------------------------------------------------
%%% # children()
%%% ----------------------------------------------------------

children() ->
    diameter_sup:tree().

%%% ----------------------------------------------------------

%% tracer/[12]

tracer(Port)
  when is_integer(Port) ->
    dbg:tracer(port, dbg:trace_port(ip, Port));

tracer(Path)
  when is_list(Path) ->
    dbg:tracer(port, dbg:trace_port(file, Path)).

tracer() ->
    dbg:tracer(process, {fun p/2, ok}).

p(T,_) ->
    io:format("+ ~p~n", [T]).

%% p/[01]

p() ->
    p([c,timestamp]).

p(T) ->
    dbg:p(all,T).

%% stop/0

stop() ->
    dbg:ctp(),
    dbg:stop_clear().

%% tpl/1
%% tp/1

tpl(T) ->
    dbg(tpl, dbg(T)).

tp(T) ->
    dbg(tp, dbg(T)).

%% dbg/1

dbg(x) ->
    [{M, x, []} || M <- [diameter_tcp,
                         diameter_etcp,
                         diameter_sctp,
                         diameter_peer_fsm,
                         diameter_watchdog]];

dbg(log) ->
    {?MODULE, log, 4};

dbg({log = F, Mods})
  when is_list(Mods) ->
    {?MODULE, F, [{['_','$1','_','_'],
                   [?ORCOND([{'==', '$1', M} || M <- Mods])],
                   []}]};

dbg({log = F, Mod}) ->
    dbg({F, [Mod]});

dbg(send) ->
    {diameter_peer, send, 2};

dbg(recv) ->
    {diameter_peer, recv, 2};

dbg(sendrecv) ->
    [{diameter_peer, send, 2},
     {diameter_peer, recv, 2}];

dbg(decode) ->
    [{diameter_codec,decode,2}];

dbg(encode) ->
    [{diameter_codec,encode,2,[]},
     {diameter_codec,encode,3,[]},
     {diameter_codec,encode,4}];

dbg(transition = T) ->
    [{?MODULE, log, [{[T,M,'_','_'],[],[]}]}
     || M <- [diameter_watchdog, diameter_peer_fsm]];

dbg(T) ->
    T.

%% dbg/2

dbg(TF, L)
  when is_list(L) ->
    {ok, lists:foldl(fun(T,A) -> {ok, X} = dbg(TF, T), [X|A] end, [], L)};

dbg(F, M)
  when is_atom(M) ->
    dbg(F, {M});

dbg(F, T)
  when is_tuple(T) ->
    [_|_] = A = tuple_to_list(T),
    {ok,_} = apply(dbg, F, case is_list(lists:last(A)) of
                               false ->
                                   A ++ [[{'_',[],[{exception_trace}]}]];
                               true ->
                                   A
                           end).

%% ===========================================================================
%% ===========================================================================

%% collect/1

collect(diameter_peer) ->
    lists:flatmap(fun peers/1, diameter:services());

collect(diameter_reg) ->
    diameter_reg:terms();

collect(Name) ->
    c(ets:info(Name), Name).

c(undefined, _) ->
    [];
c(_, Name) ->
    ets:tab2list(Name).

%% peers/1

peers(Name) ->
    peers(Name, diameter:service_info(Name, transport)).

peers(_, undefined) ->
    [];
peers(Name, {Cs,As}) ->
    mk_peer(Name, connector, Cs) ++ mk_peer(Name, acceptor, As).

mk_peer(Name, T, Ts) ->
    [[Name | mk_peer(T,Vs)] || Vs <- Ts].

mk_peer(Type, Vs) ->
    [Ref, State, Opts, WPid, TPid, SApps, Caps]
        = get_values(Vs, [ref, state, options, watchdog, peer, apps, caps]),
    [Ref, State, [{type, Type} | Opts], s(WPid), s(TPid), SApps, Caps].

get_values(Vs, Ks) ->
    [proplists:get_value(K, Vs) || K <- Ks].

s(undefined = T) ->
    T;

%% Collect states from watchdog/transport pids.
s(Pid) ->
    MRef = erlang:monitor(process, Pid),
    Pid ! {state, self()},
    receive
        {'DOWN', MRef, process, _, _} ->
            Pid;
        {Pid, _} = T ->
            erlang:demonitor(MRef, [flush]),
            T
    end.

%% fields/1

-define(FIELDS(Table), fields(Table) -> record_info(fields, Table)).

fields(diameter_config) ->
    [];

fields(T)
  when T == diameter_request;
       T == diameter_sequence ->
    fun kv/1;

fields(diameter_stats) ->
    fun({Ctr, N}) when not is_pid(Ctr) ->
            {[counter, value], [Ctr, N]};
       (_) ->
            []
    end;

?FIELDS(diameter_service);
?FIELDS(diameter_event);
?FIELDS(diameter_uri);
?FIELDS(diameter_avp);
?FIELDS(diameter_header);
?FIELDS(diameter_packet);
?FIELDS(diameter_app);
?FIELDS(diameter_caps);

fields(diameter_peer) ->
    [service, ref, state, options, watchdog, peer, applications, capabilities];

fields(diameter_reg) ->
    [property, pids];

fields(_) ->
    undefined.

kv({_,_}) ->
    [key, value];
kv(_) ->
    [].
