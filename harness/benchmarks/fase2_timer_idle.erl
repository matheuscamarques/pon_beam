-module(fase2_timer_idle).
-export([run/0]).

%% timer_idle_cpu.erl — Mede CPU consumida pelo VM sem timers ativos
%%
%% Baseline (OTP stock): timer wheel faz polling enquanto há timers.
%% PON-BEAM: notificação pontual (timerfd) — sem polling.
%%
%% Medição: erlang:statistics(runtime) — ms de CPU do próprio emulador.
%% Delta sobre 10s de idle = overhead de polling da VM.

run() ->
    {T0, _} = erlang:statistics(runtime),

    %% 10 segundos sem timers
    timer:sleep(10000),

    {T1, _} = erlang:statistics(runtime),

    #{cpu_ms_idle_10s => T1 - T0}.