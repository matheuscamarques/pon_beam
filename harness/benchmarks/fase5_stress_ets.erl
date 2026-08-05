-module(fase5_stress_ets).
-export([run/0]).

%% fase5_stress_ets.erl — Teste de estresse com alta contenção de Hot-Key no ETS
%%
%% 50 leitores e 10 escritores concorrentes disputando a mesma chave ETS por 5 segundos.
%% Mede a vazão de leituras e escritas sob a tabela hash lateral de watchers.
%%

-define(CONCURRENT_READERS, 50).
-define(CONCURRENT_WRITERS, 10).
-define(DURATION_MS, 5000).

run() ->
    Table = ets:new(pon_stress_ets, [public, named_table, set]),
    Key = hot_key,
    ets:insert(Table, {Key, 0}),
    
    Parent = self(),
    StopRef = make_ref(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Spawna 50 leitores em loop contínuo
    Readers = [spawn(fun() -> reader_loop(Table, Key, StopRef, 0, Parent) end) || _ <- lists:seq(1, ?CONCURRENT_READERS)],
    
    %% Spawna 10 escritores em loop contínuo
    Writers = [spawn(fun() -> writer_loop(Table, Key, StopRef, 0, Parent) end) || _ <- lists:seq(1, ?CONCURRENT_WRITERS)],
    
    %% Roda por 5s
    timer:sleep(?DURATION_MS),
    
    %% Envia sinal de parada
    lists:foreach(fun(Pid) -> Pid ! StopRef end, Readers ++ Writers),
    
    %% Coleta contagens
    TotalReads = collect_counts(length(Readers), 0),
    TotalWrites = collect_counts(length(Writers), 0),
    
    {T1, _} = erlang:statistics(runtime),
    
    ets:delete(Table),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    TimeMs = max(1, T1 - T0),
    #{
        duration_ms => ?DURATION_MS,
        readers_count => ?CONCURRENT_READERS,
        writers_count => ?CONCURRENT_WRITERS,
        total_reads => TotalReads,
        total_writes => TotalWrites,
        reads_per_sec => (TotalReads * 1000) / TimeMs,
        writes_per_sec => (TotalWrites * 1000) / TimeMs,
        pon_stats => Stats
    }.

reader_loop(Table, Key, StopRef, Acc, Parent) ->
    receive
        StopRef -> Parent ! {count_ack, Acc}
    after 0 ->
        [{Key, _}] = ets:lookup(Table, Key),
        reader_loop(Table, Key, StopRef, Acc + 1, Parent)
    end.

writer_loop(Table, Key, StopRef, Acc, Parent) ->
    receive
        StopRef -> Parent ! {count_ack, Acc}
    after 0 ->
        ets:insert(Table, {Key, Acc + 1}),
        writer_loop(Table, Key, StopRef, Acc + 1, Parent)
    end.

collect_counts(0, Acc) -> Acc;
collect_counts(N, Acc) ->
    receive
        {count_ack, C} -> collect_counts(N - 1, Acc + C)
    after 5000 -> Acc
    end.
