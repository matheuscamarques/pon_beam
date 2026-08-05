-module(fase4_stress_sched).
-export([run/0]).

%% fase4_stress_sched.erl — Teste de estresse com 100.000 ráfagas e dormência no eventfd
%%
%% 100 ciclos alternando entre ráfaga de 1.000 trabalhadores concorrentes
%% e repouso de 100ms (bloqueio no epoll_wait).
%%

-define(STRESS_CYCLES, 100).
-define(WORKERS_PER_CYCLE, 1000).

run() ->
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    TotalProcessed = lists:foldl(fun(_Cycle, Acc) ->
        Workers = [spawn(fun() -> Parent ! {sched_stress_ack, I} end) || I <- lists:seq(1, ?WORKERS_PER_CYCLE)],
        
        Acked = collect_acks(?WORKERS_PER_CYCLE, 0),
        
        timer:sleep(100),
        
        Acc + Acked
    end, 0, lists:seq(1, ?STRESS_CYCLES)),
    
    {T1, _} = erlang:statistics(runtime),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    TimeMs = max(1, T1 - T0),
    #{
        cycles => ?STRESS_CYCLES,
        workers_per_cycle => ?WORKERS_PER_CYCLE,
        total_processed => TotalProcessed,
        cpu_time_ms => TimeMs,
        pon_stats => Stats
    }.

collect_acks(0, Acc) -> Acc;
collect_acks(N, Acc) ->
    receive
        {sched_stress_ack, _} -> collect_acks(N - 1, Acc + 1)
    after 5000 -> Acc
    end.
