-module(fase6_compile).
-export([run/0]).

%% compile_receive.erl — Benchmark de compilação de receives com PON
%%
%% O parse transform pon_compiler converte blocos receive para
%% chamadas a pon_runtime (register_premises + receive_msg).
%%
%% Mede o tempo de compilação de um módulo real (com vários receives)
%% com e sem a transformada PON.

-define(TMP_PATH, "/tmp/pon_bench_compile.erl").

run() ->
    Src = pon_test_module_source(),
    ok = file:write_file(?TMP_PATH, Src),

    %% Compila sem PON (baseline)
    {T1, R1} = timer:tc(fun() ->
        compile:file(?TMP_PATH, [return, binary])
    end),

    %% Compila com PON (parse transform)
    {T2, R2} = timer:tc(fun() ->
        compile:file(?TMP_PATH, [return, binary,
                                 {parse_transform, pon_compiler},
                                 {d, pon_beam}])
    end),

    BaselineOk = element(1, R1) =:= ok,
    PonOk = element(1, R2) =:= ok,

    Ratio = case BaselineOk andalso PonOk of
        true -> max(1, T1) / max(1, T2);
        false -> undefined
    end,

    #{
        compile_baseline_us => T1,
        compile_pon_us => T2,
        baseline_ok => BaselineOk,
        pon_ok => PonOk,
        ratio => Ratio
    }.

pon_test_module_source() ->
    "-module(pon_bench_compile).\n"
    "-export([handle/2]).\n"
    "-compile({parse_transform, pon_compiler}).\n"
    "\n"
    "handle(State, {call, From, Req}) ->\n"
    "    receive\n"
    "        {call, From2, Req2} when Req2 > 0 ->\n"
    "            From2 ! {reply, Req2},\n"
    "            handle(State, Req2);\n"
    "        {cast, Msg} ->\n"
    "            {noreply, Msg};\n"
    "        Other ->\n"
    "            {info, Other}\n"
    "    end.\n".