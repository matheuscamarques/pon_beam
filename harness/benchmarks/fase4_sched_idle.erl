-module(fase4_sched_idle).
-export([run/0]).

run() ->
    Before = cpu_util(),
    timer:sleep(10000),
    After = cpu_util(),
    CpuDelta = case {Before, After} of
        {{B, _, _}, {A, _, _}} -> A - B;
        _ -> undefined
    end,
    #{cpu_idle_10s_delta => CpuDelta}.

cpu_util() ->
    try erlang:statistics(cpu_utilization)
    catch error:badarg -> undefined
    end.
