-module(sched_idle_cpu).
-export([run/0]).

%% sched_idle_cpu.erl — CPU do scheduler ocioso
%%
%% Mede o consumo de CPU do scheduler quando no h processos executveis.
%% Baseline (OTP stock): polling da run queue → 5-30% de um core.
%% PON-BEAM: Condition bloqueia no eventfd → 0% de CPU.

run() ->
    {Before, _, _} = erlang:statistics(cpu_utilization),
    timer:sleep(10000),
    {After, _, _} = erlang:statistics(cpu_utilization),
    #{cpu_idle_10s_delta => After - Before}.
