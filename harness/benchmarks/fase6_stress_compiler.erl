-module(fase6_stress_compiler).
-export([run/0]).

%% fase6_stress_compiler.erl — Teste de estresse de compilação AST com 50 cláusulas receive
%%
%% Compila dinamicamente 100 módulos contendo 50 cláusulas receive compostas cada.
%% Mede o tempo médio de transformação da AST e registro de Premises.
%%

-define(MODULE_COUNT, 100).
-define(TMP_PATH, "/tmp/pon_bench_stress_compile.erl").

run() ->
    code:add_patha("harness/benchmarks/lib"),
    code:add_patha("benchmarks/lib"),
    
    Src = large_receive_source(),
    ok = file:write_file(?TMP_PATH, Src),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Compila 100 iterações com parse transform
    SuccessCount = lists:foldl(fun(_I, Acc) ->
        case compile:file(?TMP_PATH, [return, binary, {i, "harness/benchmarks/lib"}, {parse_transform, pon_compiler}]) of
            {ok, _, _} -> Acc + 1;
            {ok, _, _, _} -> Acc + 1;
            _ -> Acc
        end
    end, 0, lists:seq(1, ?MODULE_COUNT)),
    
    {T1, _} = erlang:statistics(runtime),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    TimeMs = max(1, T1 - T0),
    #{
        modules_compiled => SuccessCount,
        total_time_ms => TimeMs,
        compiles_per_sec => (SuccessCount * 1000) / TimeMs,
        pon_stats => Stats
    }.

large_receive_source() ->
    Header = "-module(pon_bench_stress_compile).\n-export([handle/1]).\nhandle(State) -> receive\n",
    Clauses = lists:map(fun(I) ->
        io_lib:format("  {msg_~p, From, Val} when Val > 0 -> From ! {reply_~p, Val}, handle(State);\n", [I, I])
    end, lists:seq(1, 50)),
    Footer = "  stop -> ok\nend.\n",
    lists:flatten([Header, Clauses, Footer]).
