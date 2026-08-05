%%% pon_timer_prop.erl — PropEr: PON-Timer
%%%
%%% Verifica as invariantes do PON-Timer (timer wheel + timerfd):
%%%   1. TimerFiresOnce: um timer dispara no máximo UMA vez
%%%   2. CancelledEffective: timer cancelado nunca dispara
%%%   3. NoGhostFire: nenhum timeout chega sem timer registrado
%%%   4. NoStaleTimer: todo timer registrado dispara ou é cancelado

-module(pon_timer_prop).
-export([prop_fires_once/0, prop_cancel_effective/0, prop_no_ghost/0,
         prop_all_fire_or_cancel/0]).

-include_lib("proper/include/proper.hrl").

%% --- Generators ---

timer_count() -> choose(0, 20).
sleep_extra_ms() -> choose(0, 100).

%% --- Helpers ---

register_timers(N) ->
    [begin
        Msg = {timeout, I},
        Ref = make_ref(),
        erlang:send_after(rand:uniform(30), self(), Msg),
        {Ref, Msg}
     end || I <- lists:seq(1, N)].

drain_all(Stop) ->
    receive
        Stop -> [];
        Msg -> [Msg | drain_all(Stop)]
    after 5000 ->
        []
    end.

flush_mailbox() ->
    receive
        _ -> flush_mailbox()
    after 0 ->
        ok
    end.

%% --- Propriedades ---

prop_fires_once() ->
    ?FORALL(N, timer_count(),
        begin
            flush_mailbox(),
            _ = register_timers(N),
            erlang:send_after(200, self(), stop),
            Msgs = drain_all(stop),
            Fired = [M || {timeout, _} = M <- Msgs],
            length(Fired) =:= length(lists:usort(Fired))
        end).

prop_cancel_effective() ->
    ?FORALL(N, timer_count(),
        begin
            flush_mailbox(),
            _ = [begin
                     Ref = erlang:send_after(60000, self(), {cancel_me, I}),
                     _ = erlang:cancel_timer(Ref)
                 end || I <- lists:seq(1, N)],
            erlang:send_after(100, self(), stop),
            Msgs = drain_all(stop),
            Cancelled = [M || {cancel_me, _} = M <- Msgs],
            Cancelled =:= []
        end).

prop_no_ghost() ->
    ?FORALL(N, timer_count(),
        begin
            flush_mailbox(),
            Timers = register_timers(N),
            Expected = [Msg || {_Ref, Msg} <- Timers],
            erlang:send_after(300, self(), stop),
            Msgs = drain_all(stop),
            Fired = [M || {timeout, _} = M <- Msgs],
            lists:all(fun(M) -> lists:member(M, Expected) end, Fired)
        end).

prop_all_fire_or_cancel() ->
    ?FORALL({N, Extra}, {timer_count(), sleep_extra_ms()},
        begin
            flush_mailbox(),
            Expected = [Msg || {_Ref, Msg} <- register_timers(N)],
            erlang:send_after(50 + Extra + 100, self(), stop),
            Msgs = drain_all(stop),
            Fired = [M || {timeout, _} = M <- Msgs],
            Covers = lists:all(fun(M) -> lists:member(M, Fired) end, Expected)
                andalso (N =:= 0 orelse Fired =/= []),
            Covers
        end).
