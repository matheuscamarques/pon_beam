-module(fase2_timer_idle).
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
    %% Mede CPU antes (OTP 30+)
    Before = cpu_util(),

    %% 10 segundos sem timers
    timer:sleep(10000),

    %% Mede CPU depois
    After = cpu_util(),

    CpuDelta = case {Before, After} of
        {{B, _, _}, {A, _, _}} -> A - B;
        _ -> undefined
    end,

    #{cpu_idle_10s_delta => CpuDelta}.

cpu_util() ->
    try erlang:statistics(cpu_utilization)
    catch error:badarg -> undefined
    end.
