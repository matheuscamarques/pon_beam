%%% pon_compiler.erl — Parse transform PON-BEAM
%%%
%%% Transforma blocos `receive` para usar Premises PON.
%%% Em vez de scanning linear, cada clusula de receive vira
%%% uma Premise registrada via pon_runtime.
%%%
%%% Uso: -compile({parse_transform, pon_compiler}).

-module(pon_compiler).
-export([parse_transform/2]).

parse_transform(Forms, _Options) ->
    io:format("[pon_compiler] transformando ~s~n",
              [get_module_name(Forms)]),
    do_transform(Forms).

get_module_name([{attribute, _, module, Name} | _]) -> Name;
get_module_name([_ | Rest]) -> get_module_name(Rest);
get_module_name([]) -> unknown.

do_transform([{attribute, Line, module, Name} | Rest]) ->
    [{attribute, Line, module, Name},
     {attribute, Line, compile, {parse_transform, pon_compiler}}
     | do_transform(Rest)];
do_transform([{function, L, N, A, Cs} | Rest]) ->
    [{function, L, N, A, transform_clauses(Cs)}
     | do_transform(Rest)];
do_transform([Other | Rest]) ->
    [Other | do_transform(Rest)];
do_transform([]) -> [].

transform_clauses(Cs) ->
    [transform_clause(C) || C <- Cs].

transform_clause({clause, L, Args, Gs, Body}) ->
    {clause, L, Args, Gs, transform_body(Body)}.

transform_body([]) -> [];
transform_body([{'receive', L, Clauses} | Rest]) ->
    build_pon_receive(L, Clauses, none)
    ++ transform_body(Rest);
transform_body([{'receive', L, Clauses, After, AfterBody} | Rest]) ->
    build_pon_receive(L, Clauses, {After, AfterBody})
    ++ transform_body(Rest);
transform_body([H | Rest]) ->
    [walk_expr(H) | transform_body(Rest)].

walk_expr({call, L, {remote, M, F}, As}) ->
    {call, L, {remote, walk_expr(M), walk_expr(F)}, [walk_expr(A) || A <- As]};
walk_expr({call, L, {atom, F}, As}) ->
    {call, L, {atom, F}, [walk_expr(A) || A <- As]};
walk_expr({tuple, L, Es}) ->
    {tuple, L, [walk_expr(E) || E <- Es]};
walk_expr({cons, L, H, T}) ->
    {cons, L, walk_expr(H), walk_expr(T)};
walk_expr({match, L, P, E}) ->
    {match, L, walk_expr(P), walk_expr(E)};
walk_expr({'case', L, E, Cs}) ->
    {'case', L, walk_expr(E), transform_clauses(Cs)};
walk_expr({'if', L, Cs}) ->
    {'if', L, transform_clauses(Cs)};
walk_expr({'receive', L, Cs}) ->
    build_pon_receive(L, Cs, none);
walk_expr({'receive', L, Cs, A, AB}) ->
    build_pon_receive(L, Cs, {A, AB});
walk_expr(Other) -> Other.

%% build_pon_receive — gera cdigo PON para um receive
build_pon_receive(L, Clauses, After) ->
    MsgVar = {var, 0, 'PonMsg'},
    %% Registra Premises
    PremiseList = build_premise_list(L, Clauses),
    Register = {call, 0, {remote, 0, {atom, 0, pon_runtime},
                                     {atom, 0, register_premises}},
                          [PremiseList]},
    %% Recebe mensagem
    Recv = case After of
        none ->
            {match, 0, MsgVar,
             {call, 0, {remote, 0, {atom, 0, pon_runtime},
                                   {atom, 0, receive_msg}}, []}};
        {AfterMs, _AfterBody} ->
            {match, 0, MsgVar,
             {call, 0, {remote, 0, {atom, 0, pon_runtime},
                                   {atom, 0, receive_msg_timeout}},
                       [{integer, 0, AfterMs}]}}
    end,
    %% Dispatch baseado na mensagem recebida
    Dispatch = build_dispatch(L, Clauses, MsgVar),
    %% Cleanup
    Unreg = {call, 0, {remote, 0, {atom, 0, pon_runtime},
                                  {atom, 0, unregister_premises}}, []},
    [Register, Recv, Dispatch, Unreg].

%% build_premise_list — gera lista de padres
build_premise_list(L, Clauses) ->
    Patterns = lists:map(
        fun({clause, _CL, [Pat], _Gs, _Bd}) ->
            {tuple, 0, [pat_to_term(0, Pat),
                        {atom, 0, true},
                        {integer, 0, 0}]}
        end, Clauses),
    list_to_ast(L, Patterns).

pat_to_term(_L, {atom, _, A}) -> {atom, 0, A};
pat_to_term(_L, {integer, _, I}) -> {integer, 0, I};
pat_to_term(_L, {tuple, _, Es}) ->
    {tuple, 0, [pat_to_term(0, E) || E <- Es]};
pat_to_term(_L, {cons, _, H, T}) ->
    {cons, 0, pat_to_term(0, H), pat_to_term(0, T)};
pat_to_term(_L, {nil, _}) -> {nil, 0};
pat_to_term(_L, {var, _, '_'}) -> {atom, 0, '_'};
pat_to_term(_L, {var, _, _Name}) -> {atom, 0, '_'};
pat_to_term(_L, {match, _, P, _}) -> pat_to_term(0, P);
pat_to_term(_L, _Other) -> {atom, 0, pon_complex}.

list_to_ast(_L, []) -> {nil, 0};
list_to_ast(L, [H | T]) -> {cons, 0, H, list_to_ast(L, T)}.

build_dispatch(_L, Clauses, MsgVar) ->
    {'case', 0, MsgVar, Clauses}.
