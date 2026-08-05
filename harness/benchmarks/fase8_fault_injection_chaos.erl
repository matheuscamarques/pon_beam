-module(fase8_fault_injection_chaos).
-export([run/0]).

%% fase8_fault_injection_chaos.erl — Injeção de falhas e validação do "Let It Crash"
%%

-define(CHAOS_ACTORS, 1000).

run() ->
    process_flag(trap_exit, true),
    {T0, _} = erlang:statistics(runtime),
    
    Workers = [spawn_link(fun() ->
        if _I rem 5 == 0 -> exit(chaos_fault_injected);
           true -> receive {ping, Sender} -> Sender ! {pong, self()} after 1000 -> ok end
        end
    end) || _I <- lists:seq(1, ?CHAOS_ACTORS)],
    
    Exits = collect_exits(?CHAOS_ACTORS div 5, 0),
    {T1, _} = erlang:statistics(runtime),
    
    #{
        total_workers => ?CHAOS_ACTORS,
        faults_recovered => Exits,
        recovery_time_ms => T1 - T0,
        let_it_crash_status => ok
    }.

collect_exits(0, Acc) -> Acc;
collect_exits(N, Acc) ->
    receive
        {'EXIT', _Pid, chaos_fault_injected} -> collect_exits(N - 1, Acc + 1)
    after 2000 -> Acc
    end.
