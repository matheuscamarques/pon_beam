-module(fair_receive).
-export([run/0]).

%% fair_receive.erl — Benchmark Controle 1: Receive com mailbox pequena / vazia
%%
%% Mede latência de send+receive com N mensagens de ruído (0, 1, 10, 100).
%% Avalia o fast-path O(1) do Stock BEAM (primeira mensagem casa) vs
%% o bookkeeping por mensagem do PON (pon_in_link + notificação).
%%
%% Compara duas variantes por N:
%% - noprem: sem premissas PON (controle de paridade)
%% - prem:   com pon_register_premises (custo real do PON)

-define(ITERATIONS, 9).
-define(SIZES, [0, 1, 10, 100]).

run() ->
    NoPremResults = lists:map(fun(N) -> benchmark(N, noprem) end, ?SIZES),
    PremResults   = lists:map(fun(N) -> benchmark(N, prem) end, ?SIZES),
    #{
        variant_noprem => NoPremResults,
        variant_prem   => PremResults
    }.

benchmark(N, Mode) ->
    Latencies = [measure_scan(N, Mode) || _ <- lists:seq(1, ?ITERATIONS)],
    Median = lists:nth(length(Latencies) div 2 + 1, lists:sort(Latencies)),
    #{n => N, mode => Mode, latency_us => Median, iters => length(Latencies)}.

measure_scan(N, Mode) ->
    Parent = self(),
    Consumer = spawn(fun() -> consumer(Parent, Mode) end),

    receive
        {ready, Consumer} -> ok
    after 2000 -> error(timeout_ready)
    end,

    Noise = {nomatch, list_to_tuple(lists:seq(1, 8))},
    lists:foreach(fun(M) -> Consumer ! M end, lists:duplicate(N, Noise)),

    timer:sleep(1),

    {TimeUs, Got} = timer:tc(fun() ->
        Consumer ! {target, value},
        receive
            {done, G} -> G
        after 5000 -> error(timeout_done)
        end
    end),

    {target, value} = Got,
    TimeUs.

consumer(Parent, Mode) ->
    case Mode of
        prem ->
            try erlang:pon_register_premises([{{target, value}, true, 0}])
            catch _:_ -> ok
            end;
        noprem ->
            ok
    end,
    Parent ! {ready, self()},
    receive
        {target, Value} ->
            Parent ! {done, {target, Value}}
    end.
