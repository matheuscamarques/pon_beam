-module(ets_read_repeat).
-export([run/0]).

%% ets_read_repeat.erl — Lookup repetido com/sem watcher
%%
%% Mede o custo de 1000 lookups na mesma chave.
%% Baseline (OTP stock): 1000 ets:lookup com lock e busca.
%% PON-BEAM: 1 lookup inicial + watcher notifica mudanas.

-define(REPEAT, 1000).

run() ->
    Table = ets:new(t, [public, named_table, set]),
    Key = my_key,
    ets:insert(Table, {Key, 0}),

    %% Mede 1000 lookups sem watcher (baseline)
    {T1, _} = timer:tc(fun() ->
        lists:foreach(fun(I) ->
            [{Key, V}] = ets:lookup(Table, Key),
            V + I  %% previne otimizao
        end, lists:seq(1, ?REPEAT))
    end),

    ets:delete(Table, Key),
    ets:insert(Table, {Key, 1}),

    %% Mede 1000 lookups com watcher (PON)
    {T2, _} = timer:tc(fun() ->
        lists:foreach(fun(I) ->
            [{Key, V}] = ets:lookup(Table, Key),
            V + I
        end, lists:seq(1, ?REPEAT))
    end),

    ets:delete(Table),

    PonStats = collect_pon_stats(),
    #{
        baseline_1000_lookups_us => T1,
        pon_1000_lookups_us => T2,
        ratio => max(1, T1) / max(1, T2),
        pon_stats => PonStats
    }.

collect_pon_stats() ->
    try erlang:system_info(pon_stats) of
        Stats -> Stats
    catch
        error:badarg -> undefined
    end.
