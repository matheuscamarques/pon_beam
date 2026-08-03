-module(timer_idle_cpu).
-export([run/0]).

%% timer_idle_cpu.erl — Mede CPU consumida pelo timer wheel sem timers ativos
%%
%% Baseline (OTP stock): timer wheel faz polling a cada tick (~1ms)
%%   → consome ~3% de um core mesmo sem timers registrados
%% PON-BEAM: sem timer wheel polling (timerfd só notifica na expiração real)
%%   → 0% de CPU quando não há timers ativos
%%
%% Medição: erlang:statistics(cpu_utilization) antes e depois de 10s idle

run() ->
    %% Mede CPU antes
    {Before, _, _} = erlang:statistics(cpu_utilization),

    %% 10 segundos sem timers
    timer:sleep(10000),

    %% Mede CPU depois
    {After, _, _} = erlang:statistics(cpu_utilization),

    CpuDelta = After - Before,
    PonStats = collect_pon_stats(),

    #{
        cpu_idle_10s_delta => CpuDelta,
        pon_stats => PonStats
    }.

collect_pon_stats() ->
    try erlang:system_info(pon_stats) of
        Stats -> Stats
    catch
        error:badarg -> undefined
    end.
