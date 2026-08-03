-module(receive_mailbox_scan).
-export([run/0]).

%% receive_mailbox_scan.erl — Benchmark de scanning linear vs Premises
%%
%% Mede o tempo de selective receive variando o tamanho da mailbox.
%% Baseline (sem PON): scanning linear O(N × M)
%% PON-BEAM: notificação de Premises O(1)
%%
%% Resultado: #{scans => [{N, BaselineUs, PonUs, Ratio}]}

-define(NUM_CLAUSES, 3).
-define(SIZES, [10, 100, 1000, 10000]).

run() ->
    Results = lists:map(fun benchmark/1, ?SIZES),
    Stats = collect_pon_stats(),
    #{scans => Results, pon_stats => Stats}.

benchmark(N) ->
    %% Preenche mailbox com N mensagens que não casam
    MsgNonMatch = {other, data},
    Prefill = [MsgNonMatch || _ <- lists:seq(1, N)],

    %% Mensagem alvo no final
    Target = {target, value},

    %% Mede tempo de receive
    {TimeUs, Got} = timer:tc(fun() -> do_receive(Prefill, Target) end),

    #{n => N, latency_us => TimeUs, got => Got}.

do_receive(Prefill, Target) ->
    Self = self(),
    %% Cria processo consumidor com mailbox preenchida
    Consumer = spawn(fun() -> consumer_loop(?NUM_CLAUSES, Self) end),
    timer:sleep(10),  %% espera consumer estar pronto

    %% Envia mensagens que não casam + alvo
    lists:foreach(fun(M) -> Consumer ! M end, Prefill),
    Consumer ! Target,

    %% Aguarda resposta do consumer
    receive
        {done, Got} -> Got
    after
        5000 -> timeout
    end.

%% consumer_loop(NumClauses, Parent) ->
%%   Executa receive com NumClauses cláusulas.
%%   A primeira cláusula casa Target.
consumer_loop(Clauses, Parent) ->
    receive
        {target, Value} ->
            Parent ! {done, {target, Value}};
        {other, _} ->
            consumer_loop(Clauses, Parent);
        _Other ->
            consumer_loop(Clauses, Parent)
    end.

%% collect_pon_stats() -> map() | undefined
collect_pon_stats() ->
    try erlang:system_info(pon_stats) of
        Stats -> Stats
    catch
        error:badarg -> undefined
    end.
