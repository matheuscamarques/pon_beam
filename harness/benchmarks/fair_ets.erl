-module(fair_ets).
-export([run/0]).

%% fair_ets.erl — Benchmark Controle 3: ETS com Chaves Distintas
%%
%% 100.000 lookups (50% hit / 50% miss), 100.000 inserts e 100.000 update_counter
%% em uma tabela de 100.000 chaves distintas.
%%
%% Avalia a hash table O(1) do Stock BEAM. Com chaves distintas sem reutilização
%% de chave quente, o PON-ETS não interfere — paridade esperada de 1.0x (controle de ruído).

-define(KEYS_COUNT, 100000).

run() ->
    Table = ets:new(fair_ets_distinct, [set, public, {write_concurrency, true}]),

    %% Popula metade da tabela (50.000 chaves)
    lists:foreach(fun(I) -> ets:insert(Table, {I, I * 10}) end, lists:seq(1, ?KEYS_COUNT div 2)),

    {InsertTimeUs, ok} = timer:tc(fun() ->
        lists:foreach(fun(I) -> ets:insert(Table, {I, I}) end, lists:seq(1, ?KEYS_COUNT))
    end),

    {LookupTimeUs, Hits} = timer:tc(fun() ->
        lists:foldl(fun(I, Acc) ->
            case ets:lookup(Table, I) of
                [{I, _}] -> Acc + 1;
                [] -> Acc
            end
        end, 0, lists:seq(1, ?KEYS_COUNT * 2))
    end),

    {CounterTimeUs, ok} = timer:tc(fun() ->
        lists:foreach(fun(I) -> ets:update_counter(Table, I, {2, 1}) end, lists:seq(1, ?KEYS_COUNT))
    end),

    ets:delete(Table),

    #{
        keys_count => ?KEYS_COUNT,
        insert_time_us => InsertTimeUs,
        lookup_time_us => LookupTimeUs,
        update_counter_time_us => CounterTimeUs,
        lookup_hits => Hits,
        inserts_per_sec => (?KEYS_COUNT * 1000000.0) / max(1, InsertTimeUs),
        lookups_per_sec => (?KEYS_COUNT * 2 * 1000000.0) / max(1, LookupTimeUs),
        counters_per_sec => (?KEYS_COUNT * 1000000.0) / max(1, CounterTimeUs)
    }.
