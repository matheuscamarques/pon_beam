-module(fase1_size).
-export([run/0]).

%% receive_mailbox_size.erl — Escalabilidade: N mensagens na mailbox × latency
%%
%% Mede como o custo do selective receive escala com o tamanho da mailbox.
%% Baseline: O(N). PON-BEAM: O(1) via notificação de Premises.
%%
%% Mesma técnica do fase1_receive: consumer com UMA cláusula alvo,
%% noise que não casa (fica na fila), medição do scan.

-define(ITERATIONS, 5).
-define(SIZES, [1, 10, 100, 1000, 10000, 100000]).

run() ->
    Results = lists:map(fun benchmark/1, ?SIZES),
    #{sizes => Results}.

benchmark(N) ->
    Latencies = [measure_scan(N) || _ <- lists:seq(1, ?ITERATIONS)],
    Median = lists:nth(length(Latencies) div 2 + 1, lists:sort(Latencies)),
    #{n => N, latency_us => Median, iters => length(Latencies)}.

measure_scan(N) ->
    Parent = self(),
    Consumer = spawn(fun() -> consumer(Parent) end),

    receive
        {ready, Consumer} -> ok
    after 2000 -> error
    end,

    Noise = {nomatch, list_to_tuple(lists:seq(1, 8))},
    lists:foreach(fun(M) -> Consumer ! M end,
                  lists:duplicate(N, Noise)),
    timer:sleep(2),

    {TimeUs, _} = timer:tc(fun() ->
        Consumer ! {ziel, value},
        receive
            {consumer_done, _R} -> ok
        after 5000 -> error
        end
    end),
    TimeUs.

consumer(Parent) ->
    try erlang:pon_register_premises([{{ziel, value}, true, 0}])
    catch _:_ -> ok
    end,
    Parent ! {ready, self()},
    receive
        {ziel, V} ->
            Parent ! {consumer_done, V}
    end.