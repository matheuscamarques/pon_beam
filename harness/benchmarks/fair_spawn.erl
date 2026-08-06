-module(fair_spawn).
-export([run/0]).

%% fair_spawn.erl — Benchmark Controle 5: Spawn/Exit em Alta Concorrência
%%
%% 1. 1.000 e 10.000 spawns (sem ack — fogo e esqueça).
%% 2. 1.000 e 10.000 spawn+ack (lifecycle completo com confirmação).
%%
%% Avalia o custo de spawn (~2–15µs no Stock BEAM) sob contenção.

run() ->
    #{
        spawn_noack_1k  => run_noack(1000),
        spawn_noack_10k => run_noack(10000),
        spawn_ack_1k    => run_ack(1000),
        spawn_ack_10k   => run_ack(10000)
    }.

run_noack(N) ->
    {TimeUs, ok} = timer:tc(fun() ->
        lists:foreach(fun(_) -> spawn(fun() -> ok end) end, lists:seq(1, N))
    end),
    UsPerSpawn = TimeUs / N,
    SpawnsPerSec = (N * 1000000.0) / max(1, TimeUs),
    #{n => N, total_time_us => TimeUs, us_per_spawn => UsPerSpawn, spawns_per_sec => SpawnsPerSec}.

run_ack(N) ->
    Parent = self(),
    {TimeUs, ok} = timer:tc(fun() ->
        Pids = [spawn(fun() -> Parent ! {ack, self()} end) || _ <- lists:seq(1, N)],
        lists:foreach(fun(P) -> receive {ack, P} -> ok end end, Pids)
    end),
    UsPerSpawn = TimeUs / N,
    SpawnsPerSec = (N * 1000000.0) / max(1, TimeUs),
    #{n => N, total_time_us => TimeUs, us_per_spawn => UsPerSpawn, spawns_per_sec => SpawnsPerSec}.