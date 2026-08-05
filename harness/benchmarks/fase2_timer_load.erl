-module(fase2_timer_load).
-export([run/0]).

%% fase2_timer_load.erl — Mede latência e precisão em carga massiva de timers
%%
%% Baseline (OTP stock): 50.000 timers exigem varredura constante da Timer Wheel.
%% PON-BEAM: timers instigados via timerfd notificam individualmente o kernel sem polling.
%%

run() ->
    N = 10000,
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Spawna N timers com prazo de 500ms
    Timers = [erlang:send_after(500, Parent, {timer_done, I}) || I <- lists:seq(1, N)],
    
    %% Coleta as N notificações de expiração
    Results = collect_expirations(N, 0),
    
    {T1, _} = erlang:statistics(runtime),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        timers_created => N,
        timers_received => Results,
        total_time_ms => T1 - T0,
        pon_stats => Stats
    }.

collect_expirations(0, Acc) ->
    Acc;
collect_expirations(Count, Acc) ->
    receive
        {timer_done, _} ->
            collect_expirations(Count - 1, Acc + 1)
    after 10000 ->
        Acc
    end.
