-module(pon_diff).
-export([generate/1, generate/2]).

generate(ResultsDir) ->
    generate(ResultsDir, "Diff Report").

generate(ResultsDir, Title) ->
    BaselineDir = filename:join(ResultsDir, "baseline"),
    PonbeamDir  = filename:join(ResultsDir, "ponbeam"),
    DiffDir     = filename:join(ResultsDir, "diff"),
    _ = file:make_dir(DiffDir),

    Baseline = load_results(BaselineDir),
    PonBeam  = load_results(PonbeamDir),
    Diff     = compute_diff(Baseline, PonBeam),

    Html = render_html(Title, Diff, Baseline, PonBeam),
    OutPath = filename:join(DiffDir, "index.html"),
    ok = file:write_file(OutPath, unicode:characters_to_binary(Html)),
    io:format("[pon_diff] Relatório: ~s~n", [OutPath]),
    ok.

load_results(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:foldl(fun(F, Acc) ->
                case filename:extension(F) of
                    ".json" ->
                        Path = filename:join(Dir, F),
                        case file:consult(Path) of
                            {ok, [Data]} when is_map(Data) ->
                                case maps:get(benchmark, Data, undefined) of
                                    undefined -> Acc;
                                    Name -> maps:put(Name, Data, Acc)
                                end;
                            _ -> Acc
                        end;
                    _ -> Acc
                end
            end, #{}, Files);
        {error, _} -> #{}
    end.

compute_diff(Baseline, PonBeam) ->
    Keys = maps:keys(Baseline) ++ maps:keys(PonBeam),
    lists:foldl(fun(K, Acc) ->
        B = maps:get(K, Baseline, #{}),
        P = maps:get(K, PonBeam, #{}),
        Ratio = compute_ratio(B, P),
        maps:put(K, #{baseline => B, ponbeam => P, ratio => Ratio}, Acc)
    end, #{}, lists:usort(Keys)).

compute_ratio(#{duration_us := BD}, #{duration_us := PD}) when PD > 0 ->
    BD / PD;
compute_ratio(_, _) -> undefined.

render_html(Title, Diff, _Baseline, _PonBeam) ->
    Rows = render_rows(Diff),
    Stats = render_pon_stats(Diff),
    [
        "<!DOCTYPE html>\n"
        "<html lang=\"pt-BR\">\n"
        "<head>\n"
        "  <meta charset=\"UTF-8\">\n"
        "  <title>PON-BEAM: ", Title, "</title>\n"
        "  <style>\n"
        "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 2em; background: #0d1117; color: #c9d1d9; }\n"
        "    h1 { color: #58a6ff; border-bottom: 2px solid #30363d; padding-bottom: 0.3em; }\n"
        "    table { border-collapse: collapse; width: 100%; margin: 1em 0; }\n"
        "    th, td { border: 1px solid #30363d; padding: 0.6em 1em; text-align: left; }\n"
        "    th { background: #161b22; color: #58a6ff; font-weight: 600; }\n"
        "    tr:nth-child(even) { background: #161b22; }\n"
        "    tr:nth-child(odd) { background: #0d1117; }\n"
        "    .gain { color: #3fb950; font-weight: bold; }\n"
        "    .loss { color: #f85149; font-weight: bold; }\n"
        "    .equal { color: #8b949e; }\n"
        "    .section { margin: 2em 0; }\n"
        "    .stats { background: #161b22; padding: 1em; border-radius: 6px; }\n"
        "    code { background: #21262d; padding: 0.2em 0.4em; border-radius: 3px; font-size: 0.9em; }\n"
        "  </style>\n"
        "</head>\n"
        "<body>\n"
        "  <h1>PON-BEAM: ", Title, "</h1>\n"
        "  <p>Gerado em: ", timestamp(), "</p>\n",
        "  <div class=\"section\">\n"
        "    <h2>Comparação de desempenho</h2>\n"
        "    <table>\n"
        "      <thead><tr><th>Benchmark</th><th>Baseline</th><th>PON-BEAM</th><th>Ganho</th></tr></thead>\n"
        "      <tbody>\n",
        Rows,
        "      </tbody>\n"
        "    </table>\n"
        "  </div>\n",
        "  <div class=\"section\">\n"
        "    <h2>Contadores PON</h2>\n"
        "    <div class=\"stats\">\n",
        Stats,
        "    </div>\n"
        "  </div>\n"
        "</body>\n"
        "</html>\n"
    ].

render_rows(Diff) ->
    maps:fold(fun(Name, #{baseline := B, ponbeam := P, ratio := Ratio}, Acc) ->
        BDur = format_duration(maps:get(duration_us, B, undefined)),
        PDur = format_duration(maps:get(duration_us, P, undefined)),
        RatioStr = format_ratio(Ratio),
        Class = ratio_class(Ratio),
        NameStr = if is_atom(Name) -> atom_to_list(Name);
                     is_list(Name) -> Name;
                     true -> io_lib:format("~p", [Name])
                  end,
        [Acc,
         "<tr><td>", NameStr, "</td><td>", BDur, "</td><td>", PDur,
         "</td><td class=\"", Class, "\">", RatioStr, "</td></tr>\n",
         render_scans(B, P)]
    end, [], Diff).

%% Se o resultado do benchmark tiver latências por N (chave scans),
%% renderiza tabela aninhada por tamanho de mailbox.
render_scans(#{result := #{scans := BS}}, #{result := #{scans := PS}}) ->
    case {lists:sort(BS), lists:sort(PS)} of
        {[], _} -> [];
        {_, []} -> [];
        {SortedB, SortedP} ->
            Rows = lists:zipwith(fun(#{latency_us := BL, n := N},
                                      #{latency_us := PL}) ->
                R = case PL of 0 -> undefined; _ -> BL / PL end,
                Class = ratio_class(R),
                ["<tr><td>", integer_to_list(N), "</td><td>",
                 format_duration(BL), "</td><td>", format_duration(PL),
                 "</td><td class=\"", Class, "\">", format_ratio(R),
                 "</td></tr>\n"]
            end, SortedB, SortedP),
            ["<tr><td colspan=\"4\"><table>",
             "<thead><tr><th>N</th><th>Baseline</th><th>PON-BEAM</th>",
             "<th>Ganho</th></tr></thead><tbody>",
             Rows, "</tbody></table></td></tr>\n"]
    end;
render_scans(_, _) -> [].

render_pon_stats(Diff) ->
    PonBase = maps:fold(fun(_Name, #{ponbeam := P}, Acc) ->
        case maps:get(stats, P, #{}) of
            #{pon := Stats} when is_map(Stats) -> maps:merge(Acc, Stats);
            _ -> Acc
        end
    end, #{}, Diff),
    case map_size(PonBase) of
        0 -> "<p>Contadores PON não disponíveis (ERTS sem PON_BEAM).</p>\n";
        _ ->
            maps:fold(fun(K, V, Acc) ->
                KStr = if is_atom(K) -> atom_to_list(K);
                          is_list(K) -> K;
                          true -> io_lib:format("~p", [K])
                       end,
                [Acc, "<li><code>", KStr, "</code>: ", io_lib:format("~p", [V]), "</li>\n"]
            end, "<ul>\n", PonBase) ++ "</ul>\n"
    end.

format_duration(undefined) -> "-";
format_duration(Us) when Us < 1 -> io_lib:format("~.2fns", [float(Us * 1000)]);
format_duration(Us) when Us < 1000 -> io_lib:format("~.2fus", [float(Us)]);
format_duration(Us) when Us < 1000000 -> io_lib:format("~.2fms", [float(Us / 1000)]);
format_duration(Us) -> io_lib:format("~.2fs", [float(Us / 1000000)]).

format_ratio(undefined) -> "-";
format_ratio(R) when R >= 1.0 -> io_lib:format("~.2f×", [R]);
format_ratio(R) -> io_lib:format("~.2f×", [R]).

ratio_class(undefined) -> "equal";
ratio_class(R) when R >= 1.05 -> "gain";
ratio_class(R) when R =< 0.95 -> "loss";
ratio_class(_) -> "equal".

timestamp() ->
    {{Y, M, D}, {H, Mn, S}} = erlang:localtime(),
    io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w", [Y, M, D, H, Mn, S]).
