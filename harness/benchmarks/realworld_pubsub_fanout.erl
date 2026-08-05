-module(realworld_pubsub_fanout).
-export([run/0]).

%% realworld_pubsub_fanout.erl — Fan-out de broadcast para 20.000 atores via Direct Notify
%%
%% 1 emissor central broadcasting para 20.000 atores receptores.
%%

-define(SUBSCRIBERS, 20000).

run() ->
    Parent = self(),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Aloca 20.000 inscritos
    Subs = [spawn(fun() ->
        receive
            {broadcast, Msg} -> Parent ! {ack_sub, self(), Msg}
        after 5000 -> timeout
        end
    end) || _ <- lists:seq(1, ?SUBSCRIBERS)],
    
    %% Broadcast
    lists:foreach(fun(Pid) -> Pid ! {broadcast, payload_broad} end, Subs),
    
    %% Aguarda acks
    Acks = collect_acks(?SUBSCRIBERS, 0),
    
    {T1, _} = erlang:statistics(runtime),

    TimeMs = max(1, T1 - T0),
    #{
        subscribers => ?SUBSCRIBERS,
        total_acks => Acks,
        total_time_ms => TimeMs,
        fanout_per_sec => (?SUBSCRIBERS * 1000) / TimeMs
    }.

collect_acks(0, Acc) -> Acc;
collect_acks(N, Acc) ->
    receive
        {ack_sub, _, _} -> collect_acks(N - 1, Acc + 1)
    after 5000 -> Acc
    end.
