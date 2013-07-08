%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1997-2011. All Rights Reserved.
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
-module(gen_udp).

-export([open/1, open/2, close/1]).
-export([send/2, send/4, recv/2, recv/3, connect/3]).
-export([controlling_process/2]).
-export([fdopen/2]).

-include("inet_int.hrl").

-type hostname() :: inet:hostname().
-type ip_address() :: inet:ip_address().
-type port_number() :: 0..65535.
-type posix() :: inet:posix().
-type socket() :: port().

-spec open(Port) -> {ok, Socket} | {error, Reason} when
      Port :: port_number(),
      Socket :: socket(),
      Reason :: posix().

open(Port) -> 
    open(Port, []).

-spec open(Port, Opts) -> {ok, Socket} | {error, Reason} when
      Port :: port_number(),
      Opts :: [Opt :: term()],
      Socket :: socket(),
      Reason :: posix().

open(Port, Opts) ->
    Mod = mod(Opts, undefined),
    {ok,UP} = Mod:getserv(Port),
    Mod:open(UP, Opts).

-spec close(Socket) -> ok when
      Socket :: socket().

close(S) ->
    inet:udp_close(S).

-spec send(Socket, Address, Port, Packet) -> ok | {error, Reason} when
      Socket :: socket(),
      Address :: ip_address() | hostname(),
      Port :: port_number(),
      Packet :: string() | binary(),
      Reason :: not_owner | posix().

send(S, Address, Port, Packet) when is_port(S) ->
    case inet_db:lookup_socket(S) of
	{ok, Mod} ->
	    case Mod:getaddr(Address) of
		{ok,IP} ->
		    case Mod:getserv(Port) of
			{ok,UP} -> Mod:send(S, IP, UP, Packet);
			{error,einval} -> exit(badarg);
			Error -> Error
		    end;
		{error,einval} -> exit(badarg);
		Error -> Error
	    end;
	Error ->
	    Error
    end.

send(S, Packet) when is_port(S) ->
    case inet_db:lookup_socket(S) of
	{ok, Mod} ->
	    Mod:send(S, Packet);
	Error ->
	    Error
    end.

-spec recv(Socket, Length) ->
                  {ok, {Address, Port, Packet}} | {error, Reason} when
      Socket :: socket(),
      Length :: non_neg_integer(),
      Address :: ip_address(),
      Port :: port_number(),
      Packet :: string() | binary(),
      Reason :: not_owner | posix().

recv(S,Len) when is_port(S), is_integer(Len) ->
    case inet_db:lookup_socket(S) of
	{ok, Mod} ->
	    Mod:recv(S, Len);
	Error ->
	    Error
    end.

-spec recv(Socket, Length, Timeout) ->
                  {ok, {Address, Port, Packet}} | {error, Reason} when
      Socket :: socket(),
      Length :: non_neg_integer(),
      Timeout :: timeout(),
      Address :: ip_address(),
      Port :: port_number(),
      Packet :: string() | binary(),
      Reason :: not_owner | posix().

recv(S,Len,Time) when is_port(S) ->
    case inet_db:lookup_socket(S) of
	{ok, Mod} ->
	    Mod:recv(S, Len,Time);
	Error ->
	    Error
    end.

connect(S, Address, Port) when is_port(S) ->
    case inet_db:lookup_socket(S) of
	{ok, Mod} ->
	    case Mod:getaddr(Address) of    
		{ok, IP} ->
		    Mod:connect(S, IP, Port);
		Error ->
		    Error
	    end;
	Error ->
	    Error
    end.

-spec controlling_process(Socket, Pid) -> ok when
      Socket :: socket(),
      Pid :: pid().

controlling_process(S, NewOwner) ->
    inet:udp_controlling_process(S, NewOwner).

%%
%% Create a port/socket from a file descriptor 
%%
fdopen(Fd, Opts) ->
    Mod = mod(Opts, undefined),
    Mod:fdopen(Fd, Opts).


%% Get the udp_module, but IPv6 address overrides default IPv4
mod(Address) ->
    case inet_db:udp_module() of
	inet_udp when tuple_size(Address) =:= 8 ->
	    inet6_udp;
	Mod ->
	    Mod
    end.

%% Get the udp_module, but option udp_module|inet|inet6 overrides
mod([{udp_module,Mod}|_], _Address) ->
    Mod;
mod([inet|_], _Address) ->
    inet_udp;
mod([inet6|_], _Address) ->
    inet6_udp;
mod([{ip, Address}|Opts], _) ->
    mod(Opts, Address);
mod([{ifaddr, Address}|Opts], _) ->
    mod(Opts, Address);
mod([_|Opts], Address) ->
    mod(Opts, Address);
mod([], Address) ->
    mod(Address).
