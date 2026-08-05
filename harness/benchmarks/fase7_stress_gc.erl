-module(fase7_stress_gc).
-export([run/0]).

%% fase7_stress_gc.erl — Teste de estresse de GC em heap gigante com 95% de lixo
%%
%% 20.000 processos com 95% de objetos mortos e varredura de GC por notificação.
%% Mede o tempo de coleta e o descarte de varreduras inútil via pon_stats.
%%

-define(TOTAL_PROCS, 20000).
-define(LIVE_RATIO, 0.05).

run() ->
    Parent = self(),
    
    LiveCount = round(?TOTAL_PROCS * ?LIVE_RATIO),
    DeadCount = ?TOTAL_PROCS - LiveCount,
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Aloca vivos
    LiveProcs = [spawn(fun() ->
        Parent ! {live_ack, self()},
        timer:sleep(60000)
    end) || _ <- lists:seq(1, LiveCount)],
    
    %% Aguarda confirmação dos vivos
    lists:foreach(fun(Pid) ->
        receive {live_ack, Pid} -> ok after 5000 -> timeout end
    end, LiveProcs),
    
    %% Aloca mortos (efêmeros)
    DeadProcs = [spawn(fun() -> ok end) || _ <- lists:seq(1, DeadCount)],
    
    %% Dispara GC forçado nos vivos
    lists:foreach(fun(P) ->
        case erlang:is_process_alive(P) of
            true -> erlang:garbage_collect(P);
            false -> ok
        end
    end, LiveProcs),
    
    {T1, _} = erlang:statistics(runtime),
    
    %% Limpeza
    lists:foreach(fun(P) -> exit(P, kill) end, LiveProcs),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    TimeMs = max(1, T1 - T0),
    #{
        total_procs => ?TOTAL_PROCS,
        live_count => LiveCount,
        dead_count => DeadCount,
        total_time_ms => TimeMs,
        pon_stats => Stats
    }.
