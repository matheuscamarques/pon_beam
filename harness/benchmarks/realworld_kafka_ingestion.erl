-module(realworld_kafka_ingestion).
-export([run/0]).

%% realworld_kafka_ingestion.erl — Simula ingestão massiva Kafka com Mailbox profunda
%%
%% Worker em lote recebendo 50.000 eventos particionados.
%% Mede a latência de ponta a ponta sob pressão de mailbox.
%%

-define(KAFKA_EVENTS, 50000).

run() ->
    Self = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Simula envio massivo por tópicos particionados
    lists:foreach(fun(I) ->
        Self ! {kafka_event, Part = I rem 8, EventId = I, payload_data}
    end, lists:seq(1, ?KAFKA_EVENTS)),
    
    %% Processamento seletivo por partição
    Processed = process_partition_events(0, ?KAFKA_EVENTS, 0),
    
    {T1, _} = erlang:statistics(runtime),

    TimeMs = max(1, T1 - T0),
    #{
        total_events => ?KAFKA_EVENTS,
        processed_events => Processed,
        total_time_ms => TimeMs,
        events_per_sec => (?KAFKA_EVENTS * 1000) / TimeMs
    }.

process_partition_events(Count, Target, Acc) when Count >= Target -> Acc;
process_partition_events(Count, Target, Acc) ->
    receive
        {kafka_event, _Part, _Id, _Data} ->
            process_partition_events(Count + 1, Target, Acc + 1)
    after 5000 -> Acc
    end.
