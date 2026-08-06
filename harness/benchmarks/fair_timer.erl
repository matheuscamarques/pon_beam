-module(fair_timer).
-export([run/0]).

%% fair_timer.erl — Benchmark Controle 6: Timers em Lote e Precisão
%%
%% 1. 1.000 timers de 1ms em lote.
%% 2. 1.000 timers de 5ms em lote.
%% 3. 100 timers de 100ms.
%% 4. Precisão: desvio mediano vs deadline com 200 timers escalonados (10ms a 200ms).
%%
%% Avalia o timer wheel do Stock BEAM vs o timerfd do PON-BEAM.

run() ->
    #{
        batch_1ms   => run_timer_batch(1000, 1),
        batch_5ms   => run_timer_batch(1000, 5),
        batch_100ms => run_timer_batch(100, 100),
        precision   => run_precision_test(200)
    }.

run_timer_batch(Count, DelayMs) ->
    Parent = self(),
    {TimeUs, ok} = timer:tc(fun() ->
        _TRefs = [erlang:send_after(DelayMs, Parent, {timer_fired, I}) || I <- lists:seq(1, Count)],
        lists:foreach(fun(I) -> receive {timer_fired, I} -> ok end end, lists:seq(1, Count)),
        ok
    end),
    #{
        count => Count,
        delay_ms => DelayMs,
        total_time_us => TimeUs,
        avg_us_per_timer => TimeUs / Count
    }.

run_precision_test(Count) ->
    Parent = self(),
    T0 = erlang:monotonic_time(microsecond),
    
    lists:foreach(fun(I) ->
        TargetDelayMs = I,
        ExpectedTimeUs = T0 + TargetDelayMs * 1000,
        spawn(fun() ->
            erlang:send_after(TargetDelayMs, Parent, {prec_fired, I, ExpectedTimeUs})
        end)
    end, lists:seq(1, Count)),

    Deviations = [
        receive
            {prec_fired, _I, ExpectedUs} ->
                ActualUs = erlang:monotonic_time(microsecond),
                abs(ActualUs - ExpectedUs)
        after 5000 -> 5000000
        end || _ <- lists:seq(1, Count)
    ],

    Sorted = lists:sort(Deviations),
    MedianDevUs = lists:nth(Count div 2 + 1, Sorted),
    MaxDevUs    = lists:last(Sorted),
    AvgDevUs    = lists:sum(Deviations) / Count,

    #{
        timers_count => Count,
        median_deviation_us => MedianDevUs,
        avg_deviation_us => AvgDevUs,
        max_deviation_us => MaxDevUs
    }.