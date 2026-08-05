%%% pon_prop_run.erl — Runner das suites PropEr formais PON-BEAM
%%%
%%% Carrega um módulo de propriedades, identifica as funções prop_*()
%%% exportadas, e roda cada uma com proper:quickcheck/2, imprimindo o
%%% resultado.

-module(pon_prop_run).
-export([run/2]).

run(Module, NumTests) ->
    Mod = list_to_atom(Module),
    case code:load_file(Mod) of
        {module, _} -> ok;
        {error, Reason} ->
            io:format("~nERRO: não foi possível carregar ~s: ~p~n",
                      [Module, Reason]),
            halt(1)
    end,
    Props = exported_props(Mod),
    case Props of
        [] ->
            io:format("ERRO: nenhuma função prop_*() exportada em ~s~n",
                      [Module]),
            halt(1);
        _ ->
            run_props(Mod, Props, NumTests)
    end.

exported_props(Mod) ->
    Exports = Mod:module_info(exports),
    [F || {F, 0} <- Exports, lists:prefix("prop_", atom_to_list(F))].

run_props(_Mod, [], _Num) ->
    ok;
run_props(Mod, [Prop | Rest], Num) ->
    io:format("  ~s: ", [Prop]),
    case proper:quickcheck(Mod:Prop(), [{numtests, Num}]) of
        true ->
            io:format("OK~n"),
            run_props(Mod, Rest, Num);
        {fail, Error} ->
            io:format("FALHOU~n  Contracorrente: ~tp~n", [Error]),
            report_successes(false);
        {error, Error} ->
            io:format("FALHOU (erro): ~tp~n", [Error]),
            report_successes(false)
    end.

report_successes(false) ->
    halt(1).