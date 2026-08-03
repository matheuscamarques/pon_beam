-module(fase7_gc_scan).
-export([run/0]).

%% gc_heap_scan.erl — Benchmark de GC: heap grande com muitos objetos mortos
%%
%% Simula um heap com 90% de objetos mortos. Mede o custo do GC.
%% Baseline: scanning de razes + copia semi-space (O(heap)).
%% PON-GC: marcao por notificao (O(live)).

-define(HEAP_SIZE, 100000).  %% 100K objetos
-define(LIVE_RATIO, 0.1).    %% 10% vivos

run() ->
    %% Constri grafo de objetos
    Live = create_live_chain(round(?HEAP_SIZE * ?LIVE_RATIO)),
    Dead = create_dead_chain(round(?HEAP_SIZE * (1 - ?LIVE_RATIO))),

    %% Mede GC
    {T1, _} = timer:tc(fun() ->
        gc_full(Live ++ Dead)
    end),

    PonStats = collect_pon_stats(),
    #{
        heap_objects => ?HEAP_SIZE,
        live_objects => round(?HEAP_SIZE * ?LIVE_RATIO),
        gc_time_us => T1,
        pon_stats => PonStats
    }.

create_live_chain(N) ->
    create_live_chain(N, self()).

create_live_chain(0, _Ref) -> [];
create_live_chain(N, Ref) ->
    [spawn_link(fun() -> gc_loop(N, Ref) end)
     || _ <- lists:seq(1, N)].

create_dead_chain(N) ->
    [spawn(fun() -> die_soon() end) || _ <- lists:seq(1, N)].

die_soon() -> ok.

gc_loop(_N, Ref) ->
    Ref ! {alive, self()},
    timer:sleep(60000).

gc_full(Procs) ->
    lists:foreach(fun(P) ->
        case erlang:is_process_alive(P) of
            true -> erlang:garbage_collect(P);
            false -> ok
        end
    end, Procs).

collect_pon_stats() ->
    try erlang:system_info(pon_stats) of
        Stats -> Stats
    catch
        error:badarg -> undefined
    end.
