-module(fase3_stress_spawn).
-export([run/0]).

%% fase3_stress_spawn.erl — Teste de estresse com tempestade de 50.000 spawns
%%
%% Spawna 50.000 processos efêmeros simultâneos em ráfaga.
%% Mede a contenção e a vazão de escalonação reativa PON.
%%

-define(SPAWNS, 50000).

run() ->
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Tempestade de spawns
    Workers = [spawn(fun() -> Parent ! {spawn_done, I} end) || I <- lists:seq(1, ?SPAWNS)],
    
    %% Aguarda encerramento
    lists:foreach(fun(Pid) ->
        receive {spawn_done, _} -> ok after 10000 -> timeout end
    end, Workers),
    
    {T1, _} = erlang:statistics(runtime),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    TimeMs = max(1, T1 - T0),
    #{
        total_spawns => ?SPAWNS,
        total_time_ms => TimeMs,
        spawns_per_sec => (?SPAWNS * 1000) / TimeMs,
        pon_stats => Stats
    }.
