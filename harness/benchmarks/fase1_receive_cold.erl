-module(fase1_receive_cold).
-export([run/0]).

%% receive_mailbox_scan_cold.erl — Benchmark de selective receive scan COLD
%%
%% Mede o scan seletivo no pior caso real do OTP stock: o consumidor
%% NÃO entra em receive enquanto a mailbox é preenchida (spin em
%% message_queue_len, que apenas conta — não varre). Só depois de
%% toda a entrega concluída o consumidor entra no receive "frio",
%% tendo que varrer a fila completa para encontrar o alvo.
%%
%% A janela medida é o próprio receive (consumer-side, monotonic_time),
%% excluindo entrega/wake — o que o fase1_receive não isola.
%%
%% Baseline: scan linear O(N) dentro da janela.
%% PON-BEAM: notificação de Premises posiciona o save pointer em O(1).

-define(ITERATIONS, 7).
-define(SIZES, [1000, 5000, 10000, 25000, 50000]).

run() ->
    Results = lists:map(fun benchmark/1, ?SIZES),
    #{scans => Results}.

benchmark(N) ->
    Latencies = [measure_scan(N) || _ <- lists:seq(1, ?ITERATIONS)],
    Median = lists:nth(length(Latencies) div 2 + 1, lists:sort(Latencies)),
    #{n => N, latency_us => Median, iters => length(Latencies)}.

measure_scan(N) ->
    Parent = self(),
    Consumer = spawn(fun() -> consumer(Parent, N + 1) end),

    %% Espera a consumer estar viva (handshake, fora da janela medida)
    receive
        {ready, Consumer} -> ok
    after 2000 -> error
    end,

    %% Preenche a mailbox com N mensagens que não casam nenhuma cláusula
    %% — a consumer está em spin (fora de receive), então nada é varrido.
    Noise = {nomatch, list_to_tuple(lists:seq(1, 8))},
    lists:foreach(fun(M) -> Consumer ! M end,
                  lists:duplicate(N, Noise)),
    Consumer ! {target, value},

    %% Resposta traz a duração do receive na consumer (janela medida)
    receive
        {done, ScanUs} -> ScanUs
    after 5000 -> error
    end.

%% consumer: registra a Premise (PON), fica fora do receive até a
%% entrega completa e só então entra COLD no receive, medindo o scan.
consumer(Parent, Total) ->
    %% PON-BEAM: registra a Premise da cláusula. No baseline o BIF não
    %% existe (undef) e o benchmark roda em modo stock puro.
    try erlang:pon_register_premises([{target, value}])
    catch error:undef -> ok
    end,
    Parent ! {ready, self()},
    spin_until(Total),
    T0 = erlang:monotonic_time(microsecond),
    receive
        {target, Value} ->
            T1 = erlang:monotonic_time(microsecond),
            Parent ! {done, T1 - T0}
    after 5000 -> error
    end.

%% spin: conta mensagens (message_queue_len inclui a sig_inq), sem
%% varrer — garante entrada cold determinística, sem race de timeout.
spin_until(Total) ->
    case process_info(self(), message_queue_len) of
        {message_queue_len, L} when L >= Total -> ok;
        _ -> spin_until(Total)
    end.
