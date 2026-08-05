-module(fase3_spawn_throughput).
-export([run/0]).

%% fase3_spawn_throughput.erl — Mede vazao (spawns/sec) na criacao de processos efemeros
%%
%% Spawna N processos efemeros sequenciais/paralelos.
%% Cada worker responde um ack ao pai e morre imediatamente.
%%
%% Baseline (OTP stock): sofre latencia no ciclo de polling do scheduler.
%% PON-BEAM: notificacao imediata via erts_pon_schedule_notify.
%%

run() ->
    N = 10000,
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Spawna N workers efêmeros
    lists:foreach(fun(I) ->
        spawn(fun() -> Parent ! {ack, I} end)
    end, lists:seq(1, N)),
    
    %% Coleta as N respostas
    Acks = collect_acks(N, 0),
    
    {T1, _} = erlang:statistics(runtime),
    
    TimeMs = max(1, T1 - T0),
    OpsPerSec = (Acks * 1000) / TimeMs,

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        processes_spawned => N,
        acks_received => Acks,
        total_time_ms => TimeMs,
        spawns_per_sec => OpsPerSec,
        pon_stats => Stats
    }.

collect_acks(0, Acc) ->
    Acc;
collect_acks(Count, Acc) ->
    receive
        {ack, _} ->
            collect_acks(Count - 1, Acc + 1)
    after 10000 ->
        Acc
    end.
