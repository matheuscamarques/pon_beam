-module(fase2_timer_sparse).
-export([run/0]).

%% fase2_timer_sparse.erl — Mede varreduras evitadas com 50.000 timers de longa duração
%%
%% Cenario: 50.000 timers registrados com prazo de 60 segundos (e.g. WebSocket timeouts).
%%
%% Baseline (OTP stock): A Timer Wheel executa verificações de slot a cada tick do scheduler.
%% PON-BEAM: pon_timer_wheel_can_skip_scan aborta as varreduras via timerfd em O(1),
%%           incrementando timer_scans_avoided.
%%

run() ->
    N = 50000,
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Registra 50.000 timers para 60 segundos no futuro
    Timers = [erlang:send_after(60000, Parent, {timeout, I}) || I <- lists:seq(1, N)],
    
    %% Aguarda 5 segundos sob carga de timers inativos
    timer:sleep(5000),
    
    {T1, _} = erlang:statistics(runtime),

    %% Cancela os timers para limpar a memória
    lists:foreach(fun(TimerRef) -> erlang:cancel_timer(TimerRef) end, Timers),
    
    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        timers_active => N,
        observation_time_ms => 5000,
        cpu_time_ms => T1 - T0,
        pon_stats => Stats
    }.
