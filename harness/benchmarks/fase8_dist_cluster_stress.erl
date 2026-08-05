-module(fase8_dist_cluster_stress).
-export([run/0]).

%% fase8_dist_cluster_stress.erl — Simula disparo de notificações PON multinó
%%

-define(NODES_COUNT, 2).
-define(MSG_COUNT, 10000).

run() ->
    Self = self(),
    {T0, _} = erlang:statistics(runtime),
    
    lists:foreach(fun(I) ->
        Self ! {remote_pon_notify, I rem ?NODES_COUNT, payload}
    end, lists:seq(1, ?MSG_COUNT)),
    
    Processed = collect_remote(?MSG_COUNT, 0),
    {T1, _} = erlang:statistics(runtime),
    
    TimeMs = max(1, T1 - T0),
    #{
        cluster_nodes => ?NODES_COUNT,
        messages_transferred => Processed,
        total_time_ms => TimeMs,
        throughput_msg_sec => (?MSG_COUNT * 1000) / TimeMs
    }.

collect_remote(0, Acc) -> Acc;
collect_remote(N, Acc) ->
    receive
        {remote_pon_notify, _NodeId, _Payload} -> collect_remote(N - 1, Acc + 1)
    after 5000 -> Acc
    end.
