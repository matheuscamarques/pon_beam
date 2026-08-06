-module(fair_order).
-export([run/0]).

%% fair_order.erl — Benchmark Controle 8: Invariante de Ordenação FIFO
%%
%% Verifica a CORREÇÃO (não desempenho):
%% 1. 10.000 mensagens enviadas por 1 único sender (ordem FIFO estrita).
%% 2. 4 senders x 2.500 mensagens (ordem estrita mantida por sender).
%%
%% Retorna o campo 'ordered => true/false' em cada ERTS, comprovando que
%% o PON-BEAM respeita rigorosamente a semântica FIFO da Erlang.

-define(SINGLE_SENDER_MSGS, 10000).
-define(MULTI_SENDERS_COUNT, 4).
-define(MULTI_MSGS_PER_SENDER, 2500).

run() ->
    SingleOrdered = verify_single_sender(?SINGLE_SENDER_MSGS),
    MultiOrdered  = verify_multi_senders(?MULTI_SENDERS_COUNT, ?MULTI_MSGS_PER_SENDER),

    #{
        ordered => (SingleOrdered andalso MultiOrdered),
        single_sender_fifo => SingleOrdered,
        multi_sender_fifo => MultiOrdered,
        single_sender_count => ?SINGLE_SENDER_MSGS,
        multi_sender_total => ?MULTI_SENDERS_COUNT * ?MULTI_MSGS_PER_SENDER
    }.

verify_single_sender(Count) ->
    Parent = self(),
    Receiver = spawn(fun() -> single_receiver(Count, Parent) end),

    lists:foreach(fun(I) -> Receiver ! {msg, I} end, lists:seq(1, Count)),

    receive
        {single_result, Receiver, IsStrictFIFO} -> IsStrictFIFO
    after 10000 -> false
    end.

single_receiver(TotalCount, Parent) ->
    %% Registra premissa se disponível
    try erlang:pon_register_premises([{{msg, '_'}, true, 0}])
    catch _:_ -> ok
    end,
    IsOrdered = check_single_fifo(1, TotalCount),
    Parent ! {single_result, self(), IsOrdered}.

check_single_fifo(N, Total) when N > Total -> true;
check_single_fifo(N, Total) ->
    receive
        {msg, N} -> check_single_fifo(N + 1, Total);
        {msg, _Other} -> false
    after 5000 -> false
    end.

verify_multi_senders(SendersCount, MsgsPerSender) ->
    Parent = self(),
    Receiver = spawn(fun() -> multi_receiver(SendersCount * MsgsPerSender, Parent) end),

    Senders = [
        spawn(fun() ->
            lists:foreach(fun(Seq) -> Receiver ! {multi_msg, SId, Seq} end, lists:seq(1, MsgsPerSender))
        end)
        || SId <- lists:seq(1, SendersCount)
    ],
    _ = Senders,

    receive
        {multi_result, Receiver, IsOrdered} -> IsOrdered
    after 15000 -> false
    end.

multi_receiver(TotalExpected, Parent) ->
    try erlang:pon_register_premises([{{multi_msg, '_', '_'}, true, 0}])
    catch _:_ -> ok
    end,
    Counters = #{1 => 0, 2 => 0, 3 => 0, 4 => 0},
    IsOrdered = check_multi_fifo(0, TotalExpected, Counters),
    Parent ! {multi_result, self(), IsOrdered}.

check_multi_fifo(Received, Total, _Counters) when Received =:= Total -> true;
check_multi_fifo(Received, Total, Counters) ->
    receive
        {multi_msg, SenderId, Seq} ->
            LastSeq = maps:get(SenderId, Counters, 0),
            if
                Seq =:= LastSeq + 1 ->
                    NewCounters = maps:put(SenderId, Seq, Counters),
                    check_multi_fifo(Received + 1, Total, NewCounters);
                true ->
                    false
            end
    after 5000 -> false
    end.