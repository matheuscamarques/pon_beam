-module(bench_stock_cpu_loop).
-export([run/0]).

%% bench_stock_cpu_loop.erl — Benchmark Adversarial 4: Pure CPU Computational Workload
%%
%% Mede o desempenho de um laço de computação pura (Fibonacci e manipulação de listas)
%% sem interação de mensagens ou I/O.
%%
%% No Stock BEAM: Execução direta do laço BEAM com registros C e dispatch eficiente.
%% No PON-BEAM: Avalia se hooks de telemetria ou verificações de redução do PON afetam
%% laços computacionais puros.

-define(FIB_N, 35).
-define(REPETITIONS, 10).

run() ->
    {TotalTimeUs, Results} = timer:tc(fun() ->
        [fib(?FIB_N) || _ <- lists:seq(1, ?REPETITIONS)]
    end),

    AvgTimeUs = TotalTimeUs / ?REPETITIONS,
    
    #{
        fib_target => ?FIB_N,
        repetitions => ?REPETITIONS,
        total_time_us => TotalTimeUs,
        avg_time_per_run_us => AvgTimeUs,
        sample_result => hd(Results)
    }.

fib(0) -> 0;
fib(1) -> 1;
fib(N) when N > 1 ->
    fib(N - 1) + fib(N - 2).
