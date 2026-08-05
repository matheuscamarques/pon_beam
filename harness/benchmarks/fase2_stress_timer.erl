-module(fase2_stress_timer).
-export([run/0]).

%% fase2_stress_timer.erl — Teste de estresse com 50.000 temporizadores simultâneos
%%
%% Registra 50.000 timers de 60s em repouso por 3s.
%% Mede a eliminação de varredura na roda de temporizadores via timerfd no kernel.
%%

-define(TIMERS, 50000).
-define(IDLE_MS, 3000).

run() ->
    Self = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Registra 50.000 timers longos
    Timers = [erlang:send_after(60000, Self, {timer_event, I}) || I <- lists:seq(1, ?TIMERS)],
    
    %% Repouso de 3 segundos
    timer:sleep(?IDLE_MS),
    
    %% Cancela os timers
    lists:foreach(fun(TRef) -> erlang:cancel_timer(TRef) end, Timers),
    
    {T1, _} = erlang:statistics(runtime),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        timers_count => ?TIMERS,
        idle_duration_ms => ?IDLE_MS,
        cpu_time_ms => T1 - T0,
        pon_stats => Stats
    }.
