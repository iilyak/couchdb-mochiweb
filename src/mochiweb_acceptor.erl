%% @author Bob Ippolito <bob@mochimedia.com>
%% @copyright 2010 Mochi Media, Inc.

%% @doc MochiWeb acceptor.

-module(mochiweb_acceptor).
-author('bob@mochimedia.com').

-include("internal.hrl").

-export([start_link/3, start_link/4, init/4]).

-define(EMFILE_SLEEP_MSEC, 100).

start_link(Server, Listen, Loop) ->
    start_link(Server, Listen, Loop, []).

start_link(Server, Listen, Loop, Opts) ->
    proc_lib:spawn_link(?MODULE, init, [Server, Listen, Loop, Opts]).

do_accept(Server, Listen) ->
    T1 = os:timestamp(),
    case mochiweb_socket:transport_accept(Listen) of
        {ok, Socket} ->
            gen_server:cast(Server, {accepted, self(), timer:now_diff(os:timestamp(), T1)}),
            mochiweb_socket:finish_accept(Socket);
        Other ->
            Other
    end.

init(Server, Listen, Loop, Opts) ->
    case catch do_accept(Server, Listen) of
        {ok, Socket} ->
            call_loop(Loop, Socket, Opts);
        {error, Err} when Err =:= closed orelse
                          Err =:= esslaccept orelse
                          Err =:= timeout ->
            exit(normal);
        Other ->
            %% Mitigate out of file descriptor scenario by sleeping for a
            %% short time to slow error rate
            case Other of
                {error, emfile} ->
                    receive
                    after ?EMFILE_SLEEP_MSEC ->
                            ok
                    end;
                _ ->
                    ok
            end,
            error_logger:error_report(
              [{application, mochiweb},
               "Accept failed error",
               lists:flatten(io_lib:format("~p", [Other]))]),
            exit({error, accept_failed})
    end.

call_loop({M, F}, Socket, Opts) ->
    M:F(Socket, Opts);
call_loop({M, F, [A1]}, Socket, Opts) ->
    M:F(Socket, Opts, A1);
call_loop({M, F, A}, Socket, Opts) ->
    erlang:apply(M, F, [Socket, Opts | A]);
call_loop(Loop, Socket, Opts) ->
    Loop(Socket, Opts).
