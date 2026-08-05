-module(fase8_numa_topology_bench).
-export([run/0]).

%% fase8_numa_topology_bench.erl — Simula escalabilidade em arquitetura NUMA 64 vCPUs
%%

-define(NUMA_CORES, 64).
-define(TASKS_PER_CORE, 500).

run() ->
    Parent = self(),
    {T0, _} = erlang:statistics(runtime),
    
    Pids = [spawn(fun() ->
        Parent ! {numa_ack, self(), erlang:system_info(scheduler_id)}
    end) || _ <- lists:seq(1, ?NUMA_CORES * ?TASKS_PER_CORE)],
    
    Acks = collect_numa_acks(?NUMA_CORES * ?TASKS_PER_CORE, 0),
    {T1, _} = erlang:statistics(runtime),
    
    TimeMs = max(1, T1 - T0),
    #{
        numa_cores => ?NUMA_CORES,
        total_tasks => Acks,
        total_time_ms => TimeMs,
        numa_throughput_ops_sec => (Acks * 1000) / TimeMs
    }.

collect_numa_acks(0, Acc) -> Acc;
collect_numa_acks(N, Acc) ->
    receive
        {numa_ack, _Pid, _SchedId} -> collect_numa_acks(N - 1, Acc + 1)
    after 5000 -> Acc
    end.
