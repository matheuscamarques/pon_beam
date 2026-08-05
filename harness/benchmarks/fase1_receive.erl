-module(fase1_receive).
-export([run/0]).

%% receive_mailbox_scan.erl — Benchmark de selective receive scan
%%
%% Mede o custo do scan seletivo variando o tamanho da mailbox.
%% A mailbox é preenchida com N mensagens que NÃO casam nenhuma cláusula
%% (permanecem na fila). A mensagem alvo é enviada por último.
%%
%% Baseline (OTP stock): scan linear O(N) para encontrar o alvo.
%% PON-BEAM: notificação de Premises entrega o alvo O(1).
%%
%% A consumer tem UMA única cláusula ({target, Value}) — sem catch-all,
%% garantindo que as mensagens noise nunca sejam consumidas antes do alvo.

-define(ITERATIONS, 9).
-define(SIZES, [10, 100, 1000, 10000, 100000]).

run() ->
    Results = lists:map(fun benchmark/1, ?SIZES),
    #{scans => Results}.

benchmark(N) ->
    Latencies = [measure_scan(N) || _ <- lists:seq(1, ?ITERATIONS)],
    Median = lists:nth(length(Latencies) div 2 + 1, lists:sort(Latencies)),
    #{n => N, latency_us => Median, iters => length(Latencies)}.

measure_scan(N) ->
    Parent = self(),
    Consumer = spawn(fun() -> consumer(Parent) end),

    %% Espera a consumer entrar no receive (handshake, fora da janela medida)
    receive
        {ready, Consumer} -> ok
    after 2000 -> error
    end,

    %% Preenche a mailbox com N mensagens que não casam nenhuma cláusula
    Noise = {nomatch, list_to_tuple(lists:seq(1, 8))},
    lists:foreach(fun(M) -> Consumer ! M end,
                  lists:duplicate(N, Noise)),

    %% Pequena pausa para garantir que o envio terminou (fora da janela medida)
    timer:sleep(2),

    %% Janela medida: envia alvo + aguarda o scan + resposta
    {TimeUs, Got} = timer:tc(fun() ->
        Consumer ! {target, value},
        receive
            {done, G} -> G
        after 5000 -> error
        end
    end),

    {target, value} = Got,
    TimeUs.

%% consumer: aceita apenas {target, Value}. Mensagens {nomatch, _}
%% não casam e permanecem na mailbox — forçando o scan seletivo.
consumer(Parent) ->
    %% PON-BEAM: registra a Premise da cláusula. No baseline o BIF não
    %% existe (undef) e o benchmark roda em modo stock puro.
    try erlang:pon_register_premises([{{target, value}, true, 0}])
    catch _:_ -> ok
    end,
    Parent ! {ready, self()},
    receive
        {target, Value} ->
            Parent ! {done, {target, Value}}
    end.