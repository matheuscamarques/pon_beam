-module(fase4_sched_churn).
-export([run/0]).

%% fase4_sched_churn.erl — Simula tráfego real (Burst & Sleep Churn)
%%
%% 50 ciclos alternando entre ráfaga instantânea de 100 requisições simultâneas
%% e repouso de 200ms (Scheduler bloqueia no eventfd).
%%

-define(CYCLES, 50).
-define(WORKERS_PER_BURST, 100).

run() ->
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    TotalProcessed = lists:foldl(fun(_Cycle, Acc) ->
        %% Ráfaga de 100 workers
        Workers = [spawn(fun() -> Parent ! {churn_done, I} end) || I <- lists:seq(1, ?WORKERS_PER_BURST)],
        
        %% Coleta 100 acks
        Acked = collect_churn_acks(?WORKERS_PER_BURST, 0),
        
        %% Repouso profundo no eventfd
        timer:sleep(200),
        
        Acc + Acked
    end, 0, lists:seq(1, ?CYCLES)),
    
    {T1, _} = erlang:statistics(runtime),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        cycles => ?CYCLES,
        workers_per_burst => ?WORKERS_PER_BURST,
        total_processed => TotalProcessed,
        cpu_time_ms => T1 - T0,
        pon_stats => Stats
    }.

collect_churn_acks(0, Acc) ->
    Acc;
collect_churn_acks(Count, Acc) ->
    receive
        {churn_done, _} ->
            collect_churn_acks(Count - 1, Acc + 1)
    after 5000 ->
        Acc
    end.
