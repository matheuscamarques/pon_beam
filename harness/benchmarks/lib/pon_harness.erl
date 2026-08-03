-module(pon_harness).
-export([run/2, run_suite/2, run_benchmark/3]).

%% run(NomeBenchmark, OutputPath) -> ok
%% Executa o benchmark e salva resultado como termo Erlang.
run(Name, OutputPath) ->
    Module = ensure_loaded(Name),
    io:format("[pon_harness] ~s: iniciando...~n", [Name]),
    {TimeUs, Result} = timer:tc(fun() -> Module:run() end),
    Stats = collect_stats(),
    Data = #{
        benchmark => Name,
        duration_us => TimeUs,
        result => Result,
        stats => Stats,
        timestamp => erlang:system_time(microsecond)
    },
    Text = io_lib:format("~tp.~n", [Data]),
    ok = file:write_file(OutputPath, Text),
    io:format("[pon_harness] ~s: concluído em ~.3fms~n", [Name, TimeUs / 1000]),
    ok.

run_suite(BenchDir, OutputDir) ->
    case file:list_dir(BenchDir) of
        {ok, Files} ->
            Beams = [F || F <- Files,
                          filename:extension(F) =:= ".beam",
                          not lists:prefix(".", F)],
            lists:foreach(fun(Beam) ->
                Name = filename:rootname(Beam),
                Out = filename:join(OutputDir, Name ++ ".json"),
                run(Name, Out)
            end, Beams);
        {error, Reason} ->
            io:format("[pon_harness] erro ao ler ~s: ~p~n", [BenchDir, Reason])
    end.

run_benchmark(Name, OutputPath, CustomStats) ->
    Module = ensure_loaded(Name),
    {TimeUs, Result} = timer:tc(fun() -> Module:run() end),
    Stats = maps:merge(collect_stats(), CustomStats),
    Data = #{
        benchmark => Name,
        duration_us => TimeUs,
        result => Result,
        stats => Stats,
        timestamp => erlang:system_time(microsecond)
    },
    Text = io_lib:format("~tp.~n", [Data]),
    ok = file:write_file(OutputPath, Text),
    io:format("[pon_harness] ~s: ~.3fms~n", [Name, TimeUs / 1000]),
    ok.

collect_stats() ->
    #{
        cpu_utilization => cpu_util(),
        context_switches => erlang:statistics(context_switches),
        gc_count => gc_stats(),
        run_queue_len => erlang:statistics(total_run_queue_lengths),
        pon => collect_pon_stats()
    }.

cpu_util() ->
    try erlang:statistics(cpu_utilization) of
        {Percent, _, _} -> Percent
    catch _:_ -> undefined
    end.

gc_stats() ->
    try erlang:statistics(gc_count) of
        {Count, WordsReclaimed, PauseUs} ->
            #{count => Count, words => WordsReclaimed, pause_us => PauseUs}
    catch _:_ -> undefined
    end.

collect_pon_stats() ->
    try erlang:system_info(pon_stats) of
        Stats -> Stats
    catch
        error:badarg -> undefined
    end.

ensure_loaded(Name) ->
    Module = list_to_atom(Name),
    code:load_file(Module),
    Module.
