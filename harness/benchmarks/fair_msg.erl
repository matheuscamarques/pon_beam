-module(fair_msg).
-export([run/0]).

%% fair_msg.erl — Benchmark Controle 2: Throughput Puro de Mensagens
%%
%% 1. Ping-pong de 30.000 round-trips com mensagens {item, 7}.
%% 2. Fan-in de 8 senders x 5.000 msgs enviadas concorrentemente para 1 receiver.
%%
%% Variantes por teste:
%% - noprem: sem registro de premissas (paridade esperada)
%% - prem:   com registro de premissas nos dois lados

-define(PINGPONG_ROUNDS, 30000).
-define(FANIN_SENDERS, 8).
-define(FANIN_MSGS_PER_SENDER, 5000).

run() ->
    #{
        pingpong_noprem => run_pingpong(noprem),
        pingpong_prem   => run_pingpong(prem),
        fanin_noprem    => run_fanin(noprem),
        fanin_prem      => run_fanin(prem)
    }.

%% Ping-Pong
run_pingpong(Mode) ->
    Parent = self(),
    Responder = spawn(fun() -> responder(Mode) end),
    
    {TimeUs, ok} = timer:tc(fun() ->
        Sender = spawn(fun() -> ping_sender(Responder, ?PINGPONG_ROUNDS, Mode, Parent) end),
        receive
            {done, Sender} -> ok
        after 15000 -> error(timeout_pingpong)
        end
    end),

    TotalMsgs = ?PINGPONG_ROUNDS * 2,
    UsPerMsg = TimeUs / TotalMsgs,
    MsgsPerSec = (TotalMsgs * 1000000.0) / max(1, TimeUs),
    #{
        mode => Mode,
        rounds => ?PINGPONG_ROUNDS,
        total_time_us => TimeUs,
        us_per_msg => UsPerMsg,
        msgs_per_sec => MsgsPerSec
    }.

ping_sender(Responder, Count, Mode, Parent) ->
    case Mode of
        prem ->
            try erlang:pon_register_premises([{{pong, 7}, true, 0}])
            catch _:_ -> ok
            end;
        noprem -> ok
    end,
    ping_loop(Responder, Count),
    Responder ! stop,
    Parent ! {done, self()}.

ping_loop(_Responder, 0) -> ok;
ping_loop(Responder, N) ->
    Responder ! {item, 7, self()},
    receive
        {pong, 7} -> ping_loop(Responder, N - 1)
    end.

responder(Mode) ->
    case Mode of
        prem ->
            try erlang:pon_register_premises([{{item, 7, '_'}, true, 0}])
            catch _:_ -> ok
            end;
        noprem -> ok
    end,
    responder_loop().

responder_loop() ->
    receive
        {item, 7, From} ->
            From ! {pong, 7},
            responder_loop();
        stop -> ok
    end.

%% Fan-In
run_fanin(Mode) ->
    Parent = self(),
    Receiver = spawn(fun() -> fanin_receiver(Mode, Parent) end),

    {TimeUs, ok} = timer:tc(fun() ->
        Senders = [spawn(fun() -> fanin_sender(Receiver, ?FANIN_MSGS_PER_SENDER, Parent) end)
                   || _ <- lists:seq(1, ?FANIN_SENDERS)],
        lists:foreach(fun(S) -> receive {sender_done, S} -> ok end end, Senders),
        Receiver ! finish_fanin,
        receive
            {fanin_done, Receiver} -> ok
        after 15000 -> error(timeout_fanin)
        end
    end),

    TotalMsgs = ?FANIN_SENDERS * ?FANIN_MSGS_PER_SENDER,
    UsPerMsg = TimeUs / TotalMsgs,
    MsgsPerSec = (TotalMsgs * 1000000.0) / max(1, TimeUs),
    #{
        mode => Mode,
        senders => ?FANIN_SENDERS,
        msgs_per_sender => ?FANIN_MSGS_PER_SENDER,
        total_time_us => TimeUs,
        us_per_msg => UsPerMsg,
        msgs_per_sec => MsgsPerSec
    }.

fanin_sender(Receiver, Count, Parent) ->
    lists:foreach(fun(I) -> Receiver ! {fanin_msg, I} end, lists:seq(1, Count)),
    Parent ! {sender_done, self()}.

fanin_receiver(Mode, Parent) ->
    case Mode of
        prem ->
            try erlang:pon_register_premises([{{fanin_msg, '_'}, true, 0}])
            catch _:_ -> ok
            end;
        noprem -> ok
    end,
    fanin_receiver_loop(0, Parent).

fanin_receiver_loop(Count, Parent) ->
    receive
        {fanin_msg, _} ->
            fanin_receiver_loop(Count + 1, Parent);
        finish_fanin ->
            Parent ! {fanin_done, self()}
    end.