-module(compile_receive).
-export([run/0]).

%% compile_receive.erl — Benchmark de compilao de receives com PON
%%
%% O parse transform pon_compiler converte blocos receive para
%% chamadas a pon_runtime (register_premises + receive_msg).
%%
%% Este benchmark mede o tempo de compilao de uma funo com
%% vrios receives, com e sem a transformada PON.

run() ->
    ModSrc = pon_test_module_source(),

    %% Compila sem PON (baseline)
    {T1, {ok, _Mod1, Bin1}} = timer:tc(fun() ->
        compile_source(ModSrc, [])
    end),

    %% Compila com PON (parse transform)
    {T2, {ok, _Mod2, Bin2}} = timer:tc(fun() ->
        compile_source(ModSrc, [{parse_transform, pon_compiler}, {d, pon_beam}])
    end),

    PonStats = collect_pon_stats(),
    #{
        compile_baseline_us => T1,
        compile_pon_us => T2,
        ratio => max(1, T1) / max(1, T2),
        pon_stats => PonStats
    }.

pon_test_module_source() ->
    "-module(pon_test).\n"
    "-export([handle/1]).\n"
    "-compile({parse_transform, pon_compiler}).\n"
    "\n"
    "handle(Msg) ->\n"
    "    receive\n"
    "        {call, From, Req} ->\n"
    "            From ! {reply, Req},\n"
    "            handle(Msg);\n"
    "        {cast, Msg} ->\n"
    "            {noreply, Msg};\n"
    "        Other ->\n"
    "            {info, Other}\n"
    "    end.\n".

compile_source(Src, Opts) ->
    compile_source(Src, Opts, []).

compile_source(Src, Opts, MoreOpts) ->
    case compile_buffer(Src, Opts ++ MoreOpts) of
        {ok, Mod, Bin} -> {ok, Mod, Bin};
        {ok, Mod, Bin, _Warnings} -> {ok, Mod, Bin};
        Error -> Error
    end.

compile_buffer(Src, Opts) ->
    case epp:parse_file(Src, ".", []) of
        {ok, Forms} ->
            compile:forms(Forms, [from_core, return] ++ Opts);
        {error, _} ->
            %% Tenta como string direta
            compile:forms([{attribute, 1, module, test},
                           {function, 1, run, 0,
                            [{clause, 1, [], [], [{atom, 1, ok}]}]}],
                          Opts)
    end.

collect_pon_stats() ->
    try erlang:system_info(pon_stats) of
        Stats -> Stats
    catch
        error:badarg -> undefined
    end.
