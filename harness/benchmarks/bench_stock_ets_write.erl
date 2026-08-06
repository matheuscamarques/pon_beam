-module(bench_stock_ets_write).
-export([run/0]).

%% bench_stock_ets_write.erl — Benchmark Adversarial 3: High-Frequency ETS Write Throughput
%%
%% Mede o throughput de escritas concorrentes (ets:insert e ets:update_counter)
%% em uma tabela ETS tipo 'set' compartilhada.
%%
%% No Stock BEAM: Operação Hash O(1) com locks refinados e sem notificação.
%% No PON-BEAM: Se PON monitorar mutações de ETS via Premises, cada escrita desencadeia
%% avaliação de Premises e propagação de eventos.

-define(OPS_PER_WORKER, 50000).
-define(WORKERS, 4).

run() ->
    Table = ets:new(bench_ets_set, [set, public, {write_concurrency, true}]),
    
    %% Inicializa chaves
    lists:foreach(fun(I) -> ets:insert(Table, {I, 0}) end, lists:seq(1, 100)),

    Parent = self(),
    
    {TotalTimeUs, ok} = timer:tc(fun() ->
        Pids = [spawn(fun() -> worker(Table, ?OPS_PER_WORKER, Parent) end) || _ <- lists:seq(1, ?WORKERS)],
        collect_workers(Pids)
    end),

    ets:delete(Table),

    TotalOps = ?OPS_PER_WORKER * ?WORKERS,
    UsPerOp = TotalTimeUs / TotalOps,
    OpsPerSec = (TotalOps * 1000000.0) / max(1, TotalTimeUs),

    #{
        workers => ?WORKERS,
        total_ops => TotalOps,
        total_time_us => TotalTimeUs,
        us_per_write => UsPerOp,
        writes_per_sec => OpsPerSec
    }.

worker(_Table, 0, Parent) ->
    Parent ! {done, self()};
worker(Table, N, Parent) ->
    Key = (N rem 100) + 1,
    ets:insert(Table, {Key, N}),
    ets:update_counter(Table, Key, {2, 1}),
    worker(Table, N - 1, Parent).

collect_workers([]) -> ok;
collect_workers(Pids) ->
    receive
        {done, Pid} -> collect_workers(lists:delete(Pid, Pids))
    after 15000 ->
        error(timeout_ets_workers)
    end.
