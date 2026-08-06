-module(bench_stock_gc_nursery).
-export([run/0]).

%% bench_stock_gc_nursery.erl — Benchmark Adversarial 5: Nursery GC Trash Allocation
%%
%% Mede o desempenho em workloads que criam grandes quantidades de lixo temporário na young heap.
%%
%% No Stock BEAM: O algoritmo de cópia (Cheney) ignora dados mortos — custo ZERO para lixo não-referenciado.
%% No PON-BEAM: Se o GC incremental/notificado do PON mantiver tabelas de rastreamento ou hooks
%% de escrita, pode haver sobretaxa na varredura da heap.

-define(ITERATIONS, 50000).
-define(ALLOC_SIZE, 1000).

run() ->
    GCBefore = erlang:statistics(garbage_collection),
    
    {TotalTimeUs, ok} = timer:tc(fun() ->
        alloc_loop(?ITERATIONS)
    end),

    GCAfter = erlang:statistics(garbage_collection),
    
    GCCountDelta = element(1, GCAfter) - element(1, GCBefore),
    WordsReclaimedDelta = element(2, GCAfter) - element(2, GCBefore),

    #{
        iterations => ?ITERATIONS,
        alloc_size => ?ALLOC_SIZE,
        total_time_us => TotalTimeUs,
        gc_collections => GCCountDelta,
        words_reclaimed => WordsReclaimedDelta
    }.

alloc_loop(0) -> ok;
alloc_loop(N) ->
    %% Aloca estrutura temporária que vira lixo imediatamente no final da função
    _TrashMap = #{key => lists:seq(1, ?ALLOC_SIZE), payload => crypto_hash_dummy(N)},
    alloc_loop(N - 1).

crypto_hash_dummy(N) ->
    erlang:md5(integer_to_binary(N)).
