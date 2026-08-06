-module(bench_stock_ephemeral_spawn).
-export([run/0]).

%% bench_stock_ephemeral_spawn.erl — Benchmark Adversarial 2: Ephemeral Process Spawn Churn
%%
%% Mede o custo de alocação, inicialização e destruição de 100.000 processos
%% efémeros de curtíssima duração.
%%
%% No Stock BEAM: Inicialização rápida da PCB (Process Control Block) e heap inicial.
%% No PON-BEAM: Alocação extra de 256 buckets em type_queues, tabelas de Premises e PON hooks.

-define(NUM_PROCESSES, 100000).

run() ->
    Parent = self(),
    
    {TotalTimeUs, ok} = timer:tc(fun() ->
        spawn_workers(?NUM_PROCESSES, Parent),
        collect_replies(?NUM_PROCESSES)
    end),

    UsPerSpawn = TotalTimeUs / ?NUM_PROCESSES,
    SpawnsPerSec = (?NUM_PROCESSES * 1000000.0) / max(1, TotalTimeUs),

    #{
        processes => ?NUM_PROCESSES,
        total_time_us => TotalTimeUs,
        latency_us_per_spawn => UsPerSpawn,
        spawns_per_sec => SpawnsPerSec
    }.

spawn_workers(0, _Parent) -> ok;
spawn_workers(N, Parent) ->
    spawn(fun() -> worker(Parent) end),
    spawn_workers(N - 1, Parent).

worker(Parent) ->
    %% Processo realiza trabalho mínimo e encerra imediatamente
    _Res = 1 + 2 + 3,
    Parent ! {done, self()}.

collect_replies(0) -> ok;
collect_replies(N) ->
    receive
        {done, _Pid} -> collect_replies(N - 1)
    after 20000 ->
        error({timeout_collecting_spawns, remaining, N})
    end.
