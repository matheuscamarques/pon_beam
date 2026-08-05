-module(realworld_gc_allocator_pressure).
-export([run/0]).

%% realworld_gc_allocator_pressure.erl — Alocação de binários gigantes efêmeros
%%
%% Gera 1.000 fluxos de grandes binários efêmeros de vida curta.
%% Mede a pausa de GC Tri-Color de Dijkstra.
%%

-define(ALLOC_CYCLES, 1000).

run() ->
    {T0, _} = erlang:statistics(runtime),
    
    lists:foreach(fun(_I) ->
        Bin = <<0:(1024*1024*8)>>, # 1MB binary
        _Sub = binary:part(Bin, 0, 100),
        erlang:garbage_collect(self())
    end, lists:seq(1, ?ALLOC_CYCLES)),
    
    {T1, _} = erlang:statistics(runtime),

    TimeMs = max(1, T1 - T0),
    #{
        alloc_cycles => ?ALLOC_CYCLES,
        total_time_ms => TimeMs,
        avg_pause_ms => TimeMs / ?ALLOC_CYCLES
    }.
