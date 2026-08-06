-module(bench_stock_memory_footprint).
-export([run/0]).

%% bench_stock_memory_footprint.erl — Benchmark Adversarial 6: Process Memory Density Footprint
%%
%% Mede o consumo total de memória RAM e o footprint médio por processo ao criar
%% 50.000 processos em repouso.
%%
%% No Stock BEAM: ~2.6 KB por processo (PCB + heap inicial).
%% No PON-BEAM: Estruturas PON adicionais (type_queues 256 buckets, listas de Premises)
%% aumentam a taxa por processo.

-define(NUM_PROCS, 50000).

run() ->
    %% Força GC do orquestrador antes da medição
    erlang:garbage_collect(),
    timer:sleep(50),
    
    MemBefore = erlang:memory(processes_used),

    Pids = [spawn(fun() -> idle_loop() end) || _ <- lists:seq(1, ?NUM_PROCS)],
    
    timer:sleep(200),
    MemAfter = erlang:memory(processes_used),
    
    TotalAllocatedBytes = max(0, MemAfter - MemBefore),
    BytesPerProcess = TotalAllocatedBytes / ?NUM_PROCS,

    %% Encerra os processos
    lists:foreach(fun(P) -> P ! stop end, Pids),

    #{
        num_processes => ?NUM_PROCS,
        mem_before_bytes => MemBefore,
        mem_after_bytes => MemAfter,
        total_allocated_bytes => TotalAllocatedBytes,
        bytes_per_process => BytesPerProcess,
        kb_per_process => BytesPerProcess / 1024.0
    }.

idle_loop() ->
    receive
        stop -> ok
    end.
