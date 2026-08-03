%%% pon_runtime.erl — Runtime PON-BEAM para gerenciamento de Premises
%%%
%%% Fornece as BIFs usadas pelo cdigo gerado pelo pon_compiler.
%%% Gerencia o registro de Premises e o receive baseado em notificao.

-module(pon_runtime).
-export([register_premises/1, receive_msg/0,
         receive_msg_timeout/1, unregister_premises/0]).

%% register_premises(Patterns) -> ok
%% Registra uma lista de Premises para o processo atual.
%% Patterns = [{Pattern :: term(), Guard :: term(), Idx :: integer()}]
register_premises(Patterns) ->
    Self = self(),
    _ = [register_premise(Self, Pat, Idx)
         || {Pat, _Guard, Idx} <- Patterns],
    ok.

%% register_premise(Pid, Pattern, Idx) -> ok
register_premise(Pid, Pattern, Idx) ->
    %% NOTA: versao simplificada — apenas armazena no dicionrio
    %% do processo para demostrao.
    Premises = case get({pon_premises, Pid}) of
        undefined -> [];
        Existing -> Existing
    end,
    put({pon_premises, Pid}, [{Pattern, Idx} | Premises]),
    ok.

%% receive_msg() -> term()
%% Receive PON: retorna a primeira mensagem que casa alguma Premise.
%% Se nenhuma Premise estiver satisfeita, bloqueia (receive normal).
receive_msg() ->
    Self = self(),
    Premises = case get({pon_premises, Self}) of
        undefined -> [];
        P -> P
    end,
    receive_msg_loop(Premises, receive_msg_timeout(Self, infinity)).

receive_msg_loop(_Premises, timeout) -> timeout;
receive_msg_loop(Premises, Msg) ->
    case match_any(Premises, Msg) of
        {ok, _Idx} -> Msg;
        nomatch ->
            %% No casou — continua esperando
            receive_msg_loop(Premises, receive_msg_timeout(self(), infinity))
    end.

%% receive_msg_timeout(TimeoutMs) -> term() | timeout
receive_msg_timeout(TimeoutMs) ->
    Self = self(),
    receive_msg_timeout(Self, TimeoutMs).

receive_msg_timeout(Self, infinity) ->
    receive
        Msg -> Msg
    end;
receive_msg_timeout(Self, TimeoutMs) ->
    receive
        Msg -> Msg
    after TimeoutMs ->
        timeout
    end.

%% match_any(Premises, Msg) -> {ok, Idx} | nomatch
match_any([], _Msg) -> nomatch;
match_any([{Pat, Idx} | Rest], Msg) ->
    case match_pattern(Pat, Msg) of
        true -> {ok, Idx};
        false -> match_any(Rest, Msg)
    end.

%% match_pattern(Pattern, Term) -> boolean()
%% Pattern matching simplificado para Premises.
match_pattern(Pat, Term) when Pat =:= Term -> true;
match_pattern({}, {}) -> true;
match_pattern({PatA, PatB}, {TermA, TermB}) ->
    match_pattern(PatA, TermA) andalso match_pattern(PatB, TermB);
match_pattern({PatA, PatB, PatC}, {TermA, TermB, TermC}) ->
    match_pattern(PatA, TermA) andalso
    match_pattern(PatB, TermB) andalso
    match_pattern(PatC, TermC);
match_pattern({PatA, PatB, PatC, PatD}, {TermA, TermB, TermC, TermD}) ->
    match_pattern(PatA, TermA) andalso
    match_pattern(PatB, TermB) andalso
    match_pattern(PatC, TermC) andalso
    match_pattern(PatD, TermD);
match_pattern([P1 | P2], [T1 | T2]) ->
    match_pattern(P1, T1) andalso match_pattern(P2, T2);
match_pattern([], []) -> true;
match_pattern(Pat, _) when is_atom(Pat) -> true;  %% wildcard
match_pattern(Pat, _) when is_integer(Pat) -> false;
match_pattern(Pat, _) when is_float(Pat) -> false;
match_pattern(Pat, Term) -> Pat =:= Term.

%% unregister_premises() -> ok
unregister_premises() ->
    Self = self(),
    erase({pon_premises, Self}),
    ok.
