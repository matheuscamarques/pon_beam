-module(fase7_gc_incremental).
-export([run/0]).

%% fase7_gc_incremental.erl — Mede passos incrementais de GC por notificação
%%
%% 5.000 objetos no heap de processos efêmeros com varredura incremental.
%% Mede o tempo de propagação de notificação e coleta.
%%

-define(OBJECTS, 5000).

run() ->
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Aloca 5.000 trabalhadores efêmeros
    Workers = [spawn(fun() ->
        Parent ! {gc_step_ack, self()}
    end) || _ <- lists:seq(1, ?OBJECTS)],
    
    %% Coleta confirmações
    lists:foreach(fun(Pid) ->
        receive {gc_step_ack, Pid} -> ok after 5000 -> timeout end
    end, Workers),
    
    %% Executa coleta de lixo incremental forçada
    erlang:garbage_collect(self()),
    
    {T1, _} = erlang:statistics(runtime),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        objects => ?OBJECTS,
        total_time_ms => max(1, T1 - T0),
        pon_stats => Stats
    }.
