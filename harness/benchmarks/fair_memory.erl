-module(fair_memory).
-export([run/0]).

%% fair_memory.erl — Benchmark Controle 7: Alocação & Mortalidade de Memória
%%
%% 1. 200.000 tuplas de 16 elementos criadas e descartadas.
%% 2. 50.000 tuplas de 128 elementos criadas e descartadas.
%% 3. 100.000 maps criados e descartados.
%%
%% Reporta a contagem de GCs (gc_count) para correlacionar desvios.

-define(TUPLES_16_COUNT, 200000).
-define(TUPLES_128_COUNT, 50000).
-define(MAPS_COUNT, 100000).

run() ->
    GCBefore = get_gc_count(),

    {T16Us, _} = timer:tc(fun() ->
        alloc_tuples_16(?TUPLES_16_COUNT)
    end),

    {T128Us, _} = timer:tc(fun() ->
        alloc_tuples_128(?TUPLES_128_COUNT)
    end),

    {MapsUs, _} = timer:tc(fun() ->
        alloc_maps(?MAPS_COUNT)
    end),

    GCAfter = get_gc_count(),
    GCCountDelta = max(0, GCAfter - GCBefore),

    #{
        tuples_16_count => ?TUPLES_16_COUNT,
        tuples_16_time_us => T16Us,
        tuples_128_count => ?TUPLES_128_COUNT,
        tuples_128_time_us => T128Us,
        maps_count => ?MAPS_COUNT,
        maps_time_us => MapsUs,
        gc_count_delta => GCCountDelta
    }.

alloc_tuples_16(0) -> ok;
alloc_tuples_16(N) ->
    _T = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,N},
    alloc_tuples_16(N - 1).

alloc_tuples_128(0) -> ok;
alloc_tuples_128(N) ->
    _T = list_to_tuple(lists:duplicate(128, N)),
    alloc_tuples_128(N - 1).

alloc_maps(0) -> ok;
alloc_maps(N) ->
    _M = #{k1 => N, k2 => N*2, k3 => N*3, k4 => N*4},
    alloc_maps(N - 1).

get_gc_count() ->
    try erlang:statistics(garbage_collection) of
        {Count, _, _} -> Count
    catch _:_ -> 0
    end.