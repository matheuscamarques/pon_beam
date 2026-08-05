-module(fase5_ets_concurrent).
-export([run/0]).

%% fase5_ets_concurrent.erl — Mede contenção e throughput em leitores/escritores ETS
%%
%% 10 leitores efetuando 10.000 lookups em paralelo com escritas concorrentes.
%% Mede o tempo total e a taxa de leituras por segundo.
%%

-define(READERS, 10).
-define(LOOKUPS_PER_READER, 10000).

run() ->
    Table = ets:new(pon_bench_ets, [public, named_table, set]),
    Key = shared_key,
    ets:insert(Table, {Key, 0}),
    
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Spawna 10 leitores em paralelo
    Readers = [spawn(fun() ->
        lists:foreach(fun(I) ->
            [{Key, V}] = ets:lookup(Table, Key),
            V + I
        end, lists:seq(1, ?LOOKUPS_PER_READER)),
        Parent ! {reader_done, self()}
    end) || _ <- lists:seq(1, ?READERS)],
    
    %% Simula escrita concorrente de atualização
    ets:insert(Table, {Key, 42}),
    
    %% Aguarda o encerramento dos 10 leitores
    lists:foreach(fun(Pid) ->
        receive {reader_done, Pid} -> ok after 10000 -> timeout end
    end, Readers),
    
    {T1, _} = erlang:statistics(runtime),
    
    ets:delete(Table),
    
    TotalLookups = ?READERS * ?LOOKUPS_PER_READER,
    TimeMs = max(1, T1 - T0),
    LookupsPerSec = (TotalLookups * 1000) / TimeMs,

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        readers => ?READERS,
        total_lookups => TotalLookups,
        total_time_ms => TimeMs,
        lookups_per_sec => LookupsPerSec,
        pon_stats => Stats
    }.
