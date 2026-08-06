-module(bench_stock_fifo_pingpong).
-export([run/0]).

%% bench_stock_fifo_pingpong.erl — Benchmark Adversarial 1: Direct FIFO Ping-Pong
%%
%% Mede o desempenho do envio e recebimento direto de mensagens em FIFO
%% sem mensagens acumuladas na mailbox (N=0).
%%
%% No Stock BEAM: Troca direta de ponteiros da msg_q em O(1) puro.
%% No PON-BEAM: Potencial custo de classificação, buckets em type queues e notificações.

-define(MESSAGES, 200000).

run() ->
    Parent = self(),
    Responder = spawn(fun() -> responder() end),
    
    {TotalTimeUs, ok} = timer:tc(fun() ->
        Sender = spawn(fun() -> sender(Responder, ?MESSAGES, Parent) end),
        receive
            {done, Sender} -> ok
        after 15000 -> error(timeout)
        end
    end),

    UsPerMsg = TotalTimeUs / ?MESSAGES,
    ThroughputMsgSec = (?MESSAGES * 1000000.0) / max(1, TotalTimeUs),

    #{
        total_messages => ?MESSAGES,
        total_time_us => TotalTimeUs,
        latency_us_per_msg => UsPerMsg,
        throughput_msg_per_sec => ThroughputMsgSec
    }.

sender(Responder, Count, Parent) ->
    ping_loop(Responder, Count),
    Responder ! stop,
    Parent ! {done, self()}.

ping_loop(_Responder, 0) -> ok;
ping_loop(Responder, N) ->
    Responder ! {ping, self()},
    receive
        pong -> ping_loop(Responder, N - 1)
    end.

responder() ->
    receive
        {ping, From} ->
            From ! pong,
            responder();
        stop ->
            ok
    end.
