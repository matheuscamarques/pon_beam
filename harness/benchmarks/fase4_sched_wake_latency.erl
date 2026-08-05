-module(fase4_sched_wake_latency).
-export([run/0]).

%% fase4_sched_wake_latency.erl — Mede a distribuição de latência de acordamento (us)
%%
%% Realiza 1.000 iterações em que a VM dorme no eventfd por 10ms
%% e é imediatamente acordada por um worker.
%% Coleta min, p50, p90, p99, max em microssegundos.
%%

-define(ITERS, 1000).

run() ->
    Parent = self(),
    
    Results = lists:map(fun(_) ->
        timer:sleep(10),
        
        T0 = erlang:monotonic_time(microsecond),
        
        Worker = spawn(fun() ->
            Parent ! {wake_ack, self()}
        end),
        
        receive
            {wake_ack, Worker} ->
                T1 = erlang:monotonic_time(microsecond),
                max(1, T1 - T0)
        after 5000 ->
            1000000
        end
    end, lists:seq(1, ?ITERS)),

    Avg = lists:sum(Results) / length(Results),
    Min = lists:min(Results),
    Max = lists:max(Results),
    P50 = percentile(50, Results),
    P90 = percentile(90, Results),
    P99 = percentile(99, Results),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        iterations => ?ITERS,
        avg_latency_us => Avg,
        min_latency_us => Min,
        p50_latency_us => P50,
        p90_latency_us => P90,
        p99_latency_us => P99,
        max_latency_us => Max,
        pon_stats => Stats
    }.

percentile(P, List) ->
    Sorted = lists:sort(List),
    Index = max(1, round(P / 100 * length(Sorted))),
    lists:nth(Index, Sorted).
