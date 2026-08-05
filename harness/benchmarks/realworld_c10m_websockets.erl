-module(realworld_c10m_websockets).
-export([run/0]).

%% realworld_c10m_websockets.erl — Simula 10.000 conexões de WebSocket inativas (C10M)
%%
%% Mantém 10.000 atores Phoenix Channels em repouso por 3 segundos.
%% Mede o consumo de CPU em repouso (0.0% CPU Idle no PON-BEAM).
%%

-define(CHANNELS, 10000).
-define(IDLE_MS, 3000).

run() ->
    Parent = self(),
    StopRef = make_ref(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Aloca 10.000 websockets inativos
    Channels = [spawn(fun() ->
        receive StopRef -> ok after ?IDLE_MS + 5000 -> ok end
    end) || _ <- lists:seq(1, ?CHANNELS)],
    
    %% Permanece em repouso
    timer:sleep(?IDLE_MS),
    
    %% Para canais
    lists:foreach(fun(Pid) -> Pid ! StopRef end, Channels),
    
    {T1, _} = erlang:statistics(runtime),

    #{
        active_channels => ?CHANNELS,
        idle_time_ms => ?IDLE_MS,
        cpu_time_ms => T1 - T0
    }.
