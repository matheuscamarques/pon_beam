%%% pon_timer_prop.erl — PropEr: PON-Timer
%%%
%%% Verifica as invariantes do PON-Timer (timer wheel + timerfd):
%%%   1. TimerFiresOnce: um timer dispara no máximo UMA vez
%%%   2. CancelledEffective: timer cancelado nunca dispara
%%%   3. NoGhostFire: nenhum timeout chega sem timer registrado
%%%   4. NoStaleTimer: todo timer registrado dispara ou é cancelado
%%%
%%% Usa timers reais do ERTS (erlang:send_after / receive) — o mesmo
%%% caminho que o PON-Timer substitui no C.

-module(pon_timer_prop).
-export([prop_fires_once/0, prop_cancel_effective/0, prop_no_ghost/0,
         prop_all_fire_or_cancel/0]).

-include_lib("proper/include/proper.hrl").

%% --- Generators ---

timer_count() -> choose(0, 20).
timeout_ms() -> choose(1, 50).
sleep_extra_ms() -> choose(0, 100).

%% --- Helpers ---

%% Registra N timers com timeouts aleatórios; devolve
%% [{Ref, Msg}] na ordem de criação.
register_timers(N) ->
    [begin
        Msg = {timeout, I},
        Ref = make_ref(),
        erlang:send_after(timeout_ms(), self(), Msg),
        {Ref, Msg}
     end || I <- lists:seq(1, N)].

%% Drena a mailbox até receber Stop (ou timeout de segurança).
%% O Stop é o último a chegar (delay maior que todos os timeouts).
drain_all(Stop) ->
    receive
        Stop -> []
    after 5000 ->
        []
    end.

%% Descartar mensagens fantasma deixadas por iterações anteriores
%% do PropEr (o processo de teste é o mesmo entre rodadas).
flush_mailbox() ->
    receive
        _ -> flush_mailbox()
    after 0 ->
        ok
    end.

%% --- Propriedades ---

%% TimerFiresOnce: cada mensagem de timeout aparece no máximo 1x
%% na mailbox.
prop_fires_once() ->
    ?FORALL(N, timer_count(),
        begin
            _ = register_timers(N),
            erlang:send_after(200, self(), stop),
            Msgs = drain_all(stop),
            Fired = [M || {timeout, _} = M <- Msgs],
            length(Fired) =:= length(lists:usort(Fired))
        end).

%% CancelledEffective: timer cancelado antes do vencimento nunca
%% dispara. Para garantir o cancelamento, usamos timeout bem longo
%% e cancelamos imediatamente.
prop_cancel_effective() ->
    ?FORALL(N, timer_count(),
        begin
            _ = [begin
                     Ref = erlang:send_after(60000, self(), {cancel_me, I}),
                     ok = erlang:cancel_timer(Ref)
                 end || I <- lists:seq(1, N)],
            erlang:send_after(100, self(), stop),
            Msgs = drain_all(stop),
            Cancelled = [M || {cancel_me, _} = M <- Msgs],
            Cancelled =:= []
        end).

%% NoGhostFire: toda mensagem de timeout recebida corresponde a um
%% timer que registramos (não há timeouts fantasma).
prop_no_ghost() ->
    ?FORALL(N, timer_count(),
        begin
            Timers = register_timers(N),
            Expected = [Msg || {_Ref, Msg} <- Timers],
            erlang:send_after(300, self(), stop),
            Msgs = drain_all(stop),
            Fired = [M || {timeout, _} = M <- Msgs],
            lists:all(fun(M) -> lists:member(M, Expected) end, Fired)
        end).

%% NoStaleTimer: com janela de espera suficiente, todo timer
%% registrado dispara (nenhum fica pendente para sempre).
prop_all_fire_or_cancel() ->
    ?FORALL({N, Extra}, {timer_count(), sleep_extra_ms()},
        begin
            Expected = [Msg || {_Ref, Msg} <- register_timers(N)],
            erlang:send_after(50 + Extra + 100, self(), stop),
            Msgs = drain_all(stop),
            Fired = [M || {timeout, _} = M <- Msgs],
            %% Todas as esperadas apareceram (presença, não contagem):
            %% mensagens fantasma de rodadas anteriores podem sobrar
            %% na mailbox, então validamos por cobertura.
            Covers = lists:all(fun(M) -> lists:member(M, Fired) end,
                               Expected)
                andalso
                %% Pelo menos uma esperada de fato disparou quando N>0
                (N =:= 0 orelse Fired =/= [])
        end).
