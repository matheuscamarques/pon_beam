-module(marathon_telemetry_10min).
-export([run/0]).

%% marathon_telemetry_10min.erl — Benchmark Maratona de 10 Minutos (600 Segundos)
%%
%% Executa 6 cargas simultâneas em background durante 600 segundos
%% e amostragem contínua a cada 1 segundo (600 pontos de telemetria).
%%

-define(DURATION_SECS, 600).
-define(SAMPLE_INTERVAL_MS, 1000).

run() ->
    Self = self(),
    StopRef = make_ref(),
    
    io:format("~n=== Iniciando Maratona de 10 Minutos (600s) ===~n"),
    
    %% Tabela ETS para carga
    Table = ets:new(marathon_ets, [public, named_table, set]),
    ets:insert(Table, {hot_key, 0}),
    
    %% 1. Worker de Mailbox
    MailboxWorker = spawn(fun() -> mailbox_workload(StopRef) end),
    
    %% 2. Worker de Timers
    TimerWorker = spawn(fun() -> timer_workload(StopRef) end),
    
    %% 3. Worker de Spawn Churn
    SpawnWorker = spawn(fun() -> spawn_churn_workload(StopRef) end),
    
    %% 4. Worker de ETS
    EtsWorkers = [spawn(fun() -> ets_workload(Table, StopRef) end) || _ <- lists:seq(1, 20)],
    
    %% 5. Worker de GC
    GcWorker = spawn(fun() -> gc_workload(StopRef) end),
    
    Workers = [MailboxWorker, TimerWorker, SpawnWorker, GcWorker | EtsWorkers],
    
    %% Loop de Amostragem de 600 Segundos
    Samples = sample_loop(1, ?DURATION_SECS, []),
    
    %% Para todos os workers
    lists:foreach(fun(W) -> W ! StopRef end, Workers),
    ets:delete(Table),
    
    io:format("~n=== Maratona de 10 Minutos Concluída! Coletadas ~p amostras ===~n", [length(Samples)]),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        duration_seconds => ?DURATION_SECS,
        sample_count => length(Samples),
        telemetry_samples => Samples,
        final_pon_stats => Stats
    }.

sample_loop(Sec, MaxSec, Acc) when Sec > MaxSec ->
    lists:reverse(Acc);
sample_loop(Sec, MaxSec, Acc) ->
    T0 = erlang:monotonic_time(microsecond),
    timer:sleep(?SAMPLE_INTERVAL_MS),
    T1 = erlang:monotonic_time(microsecond),
    
    SampleDurationUs = T1 - T0,
    
    {ContextSwitches, _} = try erlang:statistics(context_switches) catch _:_ -> {0, 0} end,
    MemoryTotal = erlang:memory(total),
    ProcCount = erlang:system_info(process_count),
    
    PonStats = try erlang:system_info(pon_stats) catch _:_ -> #{} end,
    
    Sample = #{
        second => Sec,
        sample_duration_us => SampleDurationUs,
        context_switches => ContextSwitches,
        memory_bytes => MemoryTotal,
        process_count => ProcCount,
        pon_stats => PonStats
    },
    
    if Sec rem 60 == 0 ->
        io:format("[Maratona 10min] ~p/600s concluídos (Processos: ~p, Memória: ~p MB)~n",
                  [Sec, ProcCount, MemoryTotal div (1024*1024)]);
       true -> ok
    end,
    
    sample_loop(Sec + 1, MaxSec, [Sample | Acc]).

mailbox_workload(StopRef) ->
    Self = self(),
    receive
        StopRef -> ok
    after 0 ->
        Self ! {unmatched, rand:uniform(1000)},
        receive
            {matched, _} -> ok
        after 1 -> ok
        end,
        mailbox_workload(StopRef)
    end.

timer_workload(StopRef) ->
    receive
        StopRef -> ok
    after 0 ->
        TRef = erlang:send_after(500, self(), timer_tick),
        receive
            timer_tick -> ok
        after 600 -> ok
        end,
        timer_workload(StopRef)
    end.

spawn_churn_workload(StopRef) ->
    receive
        StopRef -> ok
    after 0 ->
        P = spawn(fun() -> ok end),
        timer:sleep(2),
        spawn_churn_workload(StopRef)
    end.

ets_workload(Table, StopRef) ->
    receive
        StopRef -> ok
    after 0 ->
        ets:lookup(Table, hot_key),
        ets:insert(Table, {hot_key, rand:uniform(10000)}),
        ets_workload(Table, StopRef)
    end.

gc_workload(StopRef) ->
    receive
        StopRef -> ok
    after 0 ->
        _L = lists:seq(1, 5000),
        erlang:garbage_collect(self()),
        timer:sleep(50),
        gc_workload(StopRef)
    end.
