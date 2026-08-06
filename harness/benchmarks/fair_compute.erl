-module(fair_compute).
-export([run/0]).

%% fair_compute.erl — Benchmark Controle 4: Computação CPU Pura
%%
%% 1. fib(27) executado 5 vezes.
%% 2. Soma de 10.000.000 de inteiros.
%% 3. Fold de 200.000 binários.
%% 4. Operações intensivas em listas (map, filter, reverse).
%%
%% Grupo de Controle da Máquina: Nada do PON é acionado aqui.
%% Variações significativamente distantes de 1.0x indicam contaminação
%% de ambiente (térmico, NUMA, carga externa).

-define(FIB_N, 27).
-define(SUM_N, 10000000).
-define(FOLD_BIN_COUNT, 200000).
-define(LIST_OPS_SIZE, 100000).

run() ->
    {FibTimeUs, FibRes} = timer:tc(fun() ->
        [fib(?FIB_N) || _ <- lists:seq(1, 5)]
    end),

    {SumTimeUs, SumRes} = timer:tc(fun() ->
        sum_loop(?SUM_N, 0)
    end),

    {FoldTimeUs, FoldRes} = timer:tc(fun() ->
        Bins = [<<I:32>> || I <- lists:seq(1, ?FOLD_BIN_COUNT)],
        lists:foldl(fun(<<Val:32>>, Acc) -> Acc + Val end, 0, Bins)
    end),

    {ListOpsTimeUs, ListRes} = timer:tc(fun() ->
        L = lists:seq(1, ?LIST_OPS_SIZE),
        Filtered = lists:filter(fun(X) -> X rem 2 =:= 0 end, L),
        Mapped = lists:map(fun(X) -> X * 2 end, Filtered),
        lists:reverse(Mapped)
    end),

    #{
        fib_time_us => FibTimeUs,
        sum_time_us => SumTimeUs,
        fold_bin_time_us => FoldTimeUs,
        list_ops_time_us => ListOpsTimeUs,
        fib_sample => hd(FibRes),
        sum_result => SumRes,
        fold_result => FoldRes,
        list_ops_length => length(ListRes)
    }.

fib(0) -> 0;
fib(1) -> 1;
fib(N) when N > 1 -> fib(N - 1) + fib(N - 2).

sum_loop(0, Acc) -> Acc;
sum_loop(N, Acc) -> sum_loop(N - 1, Acc + N).