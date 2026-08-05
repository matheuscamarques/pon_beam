-module(fase1_stress_mailbox).
-export([run/0]).

%% fase1_stress_mailbox.erl — Teste de estresse de mailbox profunda
%%
%% Insere 50.000 mensagens não casadas na mailbox do processo.
%% Em seguida, realiza 1.000 buscas com receive PON.
%% Mede o tempo de busca em O(1) lazy vs scanning O(N*M) do stock.
%%

-define(UNMATCHED, 50000).
-define(LOOKUPS, 1000).

run() ->
    Self = self(),
    
    %% Preenche mailbox com 50.000 mensagens que não casam
    lists:foreach(fun(I) ->
        Self ! {unmatched_msg, I}
    end, lists:seq(1, ?UNMATCHED)),
    
    {T0, _} = erlang:statistics(runtime),
    
    %% Intercala 1.000 buscas casadas
    lists:foreach(fun(I) ->
        Self ! {target_msg, I},
        receive
            {target_msg, I} -> ok
        after 5000 -> timeout
        end
    end, lists:seq(1, ?LOOKUPS)),
    
    {T1, _} = erlang:statistics(runtime),
    
    %% Limpa mailbox
    flush_mailbox(),

    Stats = try erlang:system_info(pon_stats)
            catch _:_ -> #{}
            end,

    #{
        unmatched_messages => ?UNMATCHED,
        lookups => ?LOOKUPS,
        total_time_ms => max(1, T1 - T0),
        ops_per_sec => (?LOOKUPS * 1000) / max(1, T1 - T0),
        pon_stats => Stats
    }.

flush_mailbox() ->
    receive
        _ -> flush_mailbox()
    after 0 -> ok
    end.
