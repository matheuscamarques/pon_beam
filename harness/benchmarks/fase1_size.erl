-module(receive_mailbox_size).
-export([run/0]).

%% receive_mailbox_size.erl — Escalabilidade: N mensagens na mailbox × latency
%%
%% Mede como o custo do receive escala com o tamanho da mailbox.
%% Baseline: O(N). PON-BEAM: O(1).
%%
%% Resultado: #{sizes => [{N, BaselineUs, PonUs}]}

-define(SIZES, [1, 10, 100, 1000, 10000, 100000]).

run() ->
    Results = lists:map(fun benchmark/1, ?SIZES),
    #{sizes => Results}.

benchmark(N) ->
    Self = self(),
    MsgNonMatch = {nomatch, list_to_tuple(lists:seq(1, 10))},
    Target = {ziel, value},
    Prefill = [MsgNonMatch || _ <- lists:seq(1, N)],

    Consumer = spawn(fun() -> consumer(Self) end),
    timer:sleep(5),

    %% Envia preenchimento
    lists:foreach(fun(M) -> Consumer ! M end, Prefill),
    timer:sleep(5),

    %% Mede receive da mensagem alvo
    {TimeUs, _} = timer:tc(fun() ->
        Consumer ! Target,
        receive {consumer_done, R} -> R end
    end),

    #{n => N, latency_us => TimeUs}.

consumer(Parent) ->
    receive
        {ziel, V} ->
            Parent ! {consumer_done, V};
        _ ->
            consumer(Parent)
    end.
