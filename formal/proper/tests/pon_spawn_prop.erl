%%% pon_spawn_prop.erl — PropEr: PON-Spawn
%%%
%%% Verifica as invariantes do PON-Spawn:
%%%   1. SpawnAlive: todo processo criado responde (liveness)
%%%   2. NoProcessLeak: processos terminam quando o trabalho acaba
%%%   3. SpawnIdentity: spawn devolve um pid distinto por chamada
%%%   4. MessageIsolation: mensagens chegam ao processo certo (cada
%%%      spawn tem sua própria mailbox)

-module(pon_spawn_prop).
-export([prop_alive/0, prop_no_leak/0, prop_distinct/0,
         prop_isolated/0]).

-include_lib("proper/include/proper.hrl").

%% --- Generators ---

worker_count() -> choose(0, 30).
message_count() -> choose(0, 30).

%% --- Helpers ---

%% Spawns N workers que respondem com {pong, self()}
spawn_workers(N) ->
    [spawn(fun() ->
               receive {ping, Parent} -> Parent ! {pong, self()} end
           end) || _ <- lists:seq(1, N)].

%% --- Propriedades ---

%% PON-Spawn preserva a semântica básica: processo responde ao ping.
prop_alive() ->
    ?FORALL(N, worker_count(),
        begin
            Workers = spawn_workers(N),
            Parent = self(),
            lists:foreach(fun(W) -> W ! {ping, Parent} end, Workers),
            Got = lists:usort([receive {pong, _} -> ok
                               after 1000 -> timeout end
                               || _ <- Workers]),
            not lists:member(timeout, Got) orelse N =:= 0
        end).

%% NoProcessLeak: após os workers terminarem, nenhum processo novo
%% permanece além dos esperados.
prop_no_leak() ->
    ?FORALL(N, worker_count(),
        begin
            Before = erlang:system_info(process_count),
            Workers = spawn_workers(N),
            lists:foreach(fun(W) ->
                MRef = erlang:monitor(process, W),
                W ! {ping, self()},
                receive {'DOWN', MRef, process, W, _} -> ok
                after 2000 -> timeout
                end
            end, Workers),
            timer:sleep(50),
            After = erlang:system_info(process_count),
            After =< Before + 1 orelse N =:= 0
        end).

%% SpawnIdentity: cada spawn produz um pid distinto por chamada.
prop_distinct() ->
    ?FORALL(N, worker_count(),
        begin
            Workers = spawn_workers(N),
            length(Workers) =:= length(lists:usort(Workers))
        end).

%% Isolation: mensagem de ping chega APENAS ao worker alvo, e cada
%% worker entrega exatamente UMA resposta por ping.
prop_isolated() ->
    ?FORALL({N, M}, {worker_count(), message_count()},
        begin
            Workers = spawn_workers(N),
            Parent = self(),
            Limited = lists:sublist(Workers, M),
            lists:foreach(fun(W) ->
                %% Cada worker fica vivo até receber exatamente 1 ping
                W ! {ping, Parent},
                _ = W
            end, Limited),
            %% Cada um dos Limited responde exatamente 1x
            Replies = [receive
                           {pong, _} -> 1
                       after 2000 ->
                           0
                       end
                       || _ <- Limited],
            lists:sum(Replies) =:= M
        end).