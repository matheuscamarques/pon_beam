-module(fase4_sched_idle).
-export([run/0]).

%% scheduler_idle_cpu.erl — Mede CPU do VM com scheduler ocioso
%%
%% Baseline: scheduler acorda periodicamente (polling).
%% PON-BEAM: eventfd/Condition notifica pontualmente.
%%
%% Medição: erlang:statistics(runtime) — ms de CPU do próprio emulador.
%% Delta sobre 10s com 0 processos = overhead de idle do scheduler.

run() ->
    {T0, _} = erlang:statistics(runtime),

    %% 10 segundos ocioso (0 processos ativos)
    timer:sleep(10000),

    {T1, _} = erlang:statistics(runtime),

    #{cpu_ms_idle_10s => T1 - T0}.