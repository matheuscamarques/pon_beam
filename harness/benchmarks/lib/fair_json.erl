-module(fair_json).
-export([dump/0, dump/1]).

%% fair_json.erl — Exporta os cenários da suíte fair (fortaleza da BEAM)
%% dos resultados do harness para JSON real, consumível por
%% generate_charts.py. Uso:
%%   erl -noshell -pa lib -eval 'fair_json:dump("harness/results/latest")'
%%
%% Os arquivos .json do harness são termos Erlang (~tp); este módulo os
%% lê, pareia os cenários baseline/ponbeam e escreve:
%%   <root>/fair_data.json
%% com entradas {name, base_us, pon_us, ratio} (ratio = base/pon,
%% >1 = PON mais rápido, <1 = regressão).

dump() -> dump("harness/results/latest").

dump(Root) ->
    BaseDir = filename:join(Root, "baseline"),
    PonDir  = filename:join(Root, "ponbeam"),
    B = load_fair(BaseDir),
    P = load_fair(PonDir),
    Scenarios = lists:sort(lists:usort(maps:keys(B) ++ maps:keys(P))),
    Rows = [begin
                BT = maps:get(time_us, maps:get(S, B, #{}), undefined),
                PT = maps:get(time_us, maps:get(S, P, #{}), undefined),
                Ratio = case {BT, PT} of
                            {X, Y} when is_integer(X), is_integer(Y), Y > 0 ->
                                X / Y;
                            _ -> undefined
                        end,
                #{<<"name">> => list_to_binary(atom_to_list(S)),
                  <<"base_us">> => nullable(BT),
                  <<"pon_us">> => nullable(PT),
                  <<"ratio">> => nullable(Ratio)}
            end || S <- Scenarios],
    Json = encode(Rows),
    Out = filename:join(Root, "fair_data.json"),
    ok = file:write_file(Out, Json),
    io:format("[fair_json] ~p cenários escritos em ~s~n", [length(Rows), Out]),
    ok.

nullable(undefined) -> null;
nullable(N) when is_number(N) -> N.

load_fair(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:foldl(fun(F, Acc) ->
                case filename:extension(F) of
                    ".json" ->
                        Path = filename:join(Dir, F),
                        case file:consult(Path) of
                            {ok, [Data]} when is_map(Data) ->
                                case maps:get(result, Data, #{}) of
                                    #{fair := L} when is_list(L) ->
                                        lists:foldl(fun(Sc, A) ->
                                            case maps:get(scenario, Sc, undefined) of
                                                undefined -> A;
                                                Name -> maps:put(Name, Sc, A)
                                            end
                                        end, Acc, L);
                                    _ -> Acc
                                end;
                            _ -> Acc
                        end;
                    _ -> Acc
                end
            end, #{}, Files);
        {error, _} -> #{}
    end.

%% Mini-encoder JSON (apenas strings, números e null — o suficiente).
encode(Proplist) ->
    [<<"[">>, lists:join(<<",">>, [encode_obj(M) || M <- Proplist]), <<"]">>].

encode_obj(M) ->
    Keys = lists:sort(maps:keys(M)),
    Pairs = [[encode_key(K), <<":">>, encode_value(maps:get(K, M))] || K <- Keys],
    [<<"{">>, lists:join(<<",">>, [iolist_to_binary(P) || P <- Pairs]), <<"}">>].

encode_key(K) when is_binary(K) -> encode_value(K).

encode_value(null) -> <<"null">>;
encode_value(N) when is_integer(N) -> integer_to_binary(N);
encode_value(N) when is_float(N) ->
    io_lib:format("~.3f", [N]);
encode_value(B) when is_binary(B) ->
    Esc = binary:replace(binary:replace(B, <<"\\">>, <<"\\\\">>, [global]),
                         <<"\"">>, <<"\\\"">>, [global]),
    [<<"\"">>, Esc, <<"\"">>];
encode_value(Other) -> encode_value(iolist_to_binary(io_lib:format("~p", [Other]))).