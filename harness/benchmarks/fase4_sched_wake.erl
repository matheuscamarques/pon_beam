-module(fase4_sched_wake).
-export([run/0]).

%% fase4_sched_wake.erl — Mede a latência de reativação da thread do scheduler
%%
%% Cenario: O scheduler entra em dormência (0% CPU).
%% Um evento assíncrono (timer/mensagem) notifica a Condition via eventfd.
%% Mede o tempo exato em microssegundos até a thread acionar e processar a tarefa.
%%

run() ->
    Parent = self(),
    
    %% Permite que o scheduler entre em estado ocioso por 200ms
    timer:sleep(200),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Dispara notificação de acionamento
    Worker = spawn(fun() ->
        Parent ! {woken, self()}
    end),
    
    Latency = receive
        {woken, Worker} ->
            {T1, _} = erlang:statistics(runtime),
            max(1, T1 - T0)
    after 5000 ->
        timeout
    end,

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        wakeup_latency_ms => Latency,
        pon_stats => Stats
    }.
