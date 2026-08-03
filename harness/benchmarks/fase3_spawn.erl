-module(spawn_latency).
-export([run/0]).

%% spawn_latency.erl — Mede latncia entre spawn e primeira execuo
%%
%% Cria N processos worker que respondem imediatamente.
%% Mede o tempo entre spawn e recebimento da resposta.
%% Baseline (OTP stock): depende do ciclo de polling do scheduler.
%% PON-BEAM: notificao imediata ao scheduler.

-define(NUM_WORKERS, 1000).

run() ->
    Parent = self(),
    Results = lists:map(fun(_) ->
        {TimeUs, _} = timer:tc(fun() ->
            Worker = spawn(fun() -> Parent ! {alive, self()} end),
            receive
                {alive, Worker} -> ok
            after 1000 -> timeout
            end
        end),
        TimeUs
    end, lists:seq(1, ?NUM_WORKERS)),

    Avg = avg(Results),
    Min = lists:min(Results),
    Max = lists:max(Results),
    P99 = percentile(99, Results),
    PonStats = collect_pon_stats(),

    #{
        num_workers => ?NUM_WORKERS,
        avg_latency_us => Avg,
        min_latency_us => Min,
        max_latency_us => Max,
        p99_latency_us => P99,
        pon_stats => PonStats
    }.

avg(List) ->
    lists:sum(List) / length(List).

percentile(P, List) ->
    Sorted = lists:sort(List),
    Index = max(1, round(P / 100 * length(Sorted))),
    lists:nth(Index, Sorted).

collect_pon_stats() ->
    try erlang:system_info(pon_stats) of
        Stats -> Stats
    catch
        error:badarg -> undefined
    end.
