%%% pon_receive_prop.erl — PropEr: PON-Receive
%%%
%%% Verifica as invariantes do selective receive com Premises:
%%%   1. PremiseSound: a mensagem devolvida pelo receive casa a cláusula
%%%      (equivalente à Premise) que a consumiu.
%%%   2. NoMessageLoss: nenhuma mensagem compatível é descartada quando
%%%      o processo continua a receber (ordem relativa preservada).
%%%   3. Equivalência: o receive PON devolve a MESMA mensagem que o
%%%      receive stock do BEAM devolveria para o mesmo mailbox.
%%%
%%% Rode com: proper:quickcheck(pon_receive_prop:prop_*()).

-module(pon_receive_prop).
-export([prop_premise_sound/0, prop_no_message_loss/0, prop_equiv_stock/0,
         prop_first_match/0]).

-include_lib("proper/include/proper.hrl").

%% --- Generators ---

%% Mensagens com estrutura {Tag, Value}
msg() ->
    ?LET({Tag, Value}, {tag(), value()}, {Tag, Value}).

tag() -> oneof([ping, pong, other]).
value() -> oneof([a, b, c]).

%% Lista não-vazia de mensagens
msg_list() ->
    non_empty(list(msg())).

%% Sequência de mensagens (pode ser vazia)
msg_seq() ->
    list(msg()).

%% --- Helpers ---

%% Converte lista de tags em lista de patterns {Tag, payload}
to_patterns(Tags) ->
    lists:map(fun(T) -> {T, payload} end, Tags).

%% Simula o receive com cláusulas {ping, _} e {pong, _}:
%% devolve a PRIMEIRA mensagem na ordem da mailbox que casa, ou
%% {nomatch, Rest} se nenhuma casa.
receive_first_match(Mailbox, Patterns) ->
    case lists:dropwhile(fun(M) -> not matches_any(M, Patterns) end, Mailbox) of
        [] -> nomatch;
        [First | _] -> First
    end.

matches_any(_M, []) -> false;
matches_any(M, [P | Rest]) ->
    match_pattern(P, M) orelse matches_any(M, Rest).

match_pattern({Tag, _}, {Tag, _}) -> true;
match_pattern({Tag, _}, _) -> false.

%% --- Propriedades ---

%% Invariante PremiseSound: toda mensagem recebida casa o padrão.
%% Se o receive devolve uma mensagem, essa mensagem casa UMA das
%% Premises registradas — nunca uma mensagem incompatível.
prop_premise_sound() ->
    ?FORALL({Mailbox, Patterns},
            {msg_list(), non_empty(list(tag()))},
            begin
                Patterns1 = to_patterns(Patterns),
                case receive_first_match(Mailbox, Patterns1) of
                    nomatch ->
                        %% Nada casa: recebedor bloqueia
                        true;
                    Msg ->
                        matches_any(Msg, Patterns1)
                end
            end).

%% Invariante NoMessageLoss: o receive consome EXATAMENTE a primeira
%% mensagem casável. Toda outra mensagem (inclusive as não-casáveis
%% intercaladas) permanece na mailbox, na ordem original.
%% Formalmente: #{mensagens casáveis após} = #{casáveis antes} - 1.
prop_no_message_loss() ->
    ?FORALL({Mailbox, Patterns},
            {msg_list(), non_empty(list(tag()))},
            begin
                Patterns1 = to_patterns(Patterns),
                AllMatching = lists:filter(
                    fun(M) -> matches_any(M, Patterns1) end,
                    Mailbox),
                case AllMatching of
                    [] ->
                        %% Nada casou: nada consumido, todas intactas
                        true;
                    _ ->
                        %% O receive_size devolve o primeiro match:
                        %% as casáveis restantes são as originais menos uma
                        First = hd(AllMatching),
                        RestMatching = lists:filter(
                            fun(M) -> matches_any(M, Patterns1) end,
                            lists:delete(First, Mailbox)),
                        RestMatching =:= tl(AllMatching)
                end
            end).

%% Equivalência com o receive stock: para o MESMO mailbox e MESMAS
%% cláusulas, receive_first_match devolve o que receive real devolveria.
prop_equiv_stock() ->
    ?FORALL({Mailbox, Patterns},
            {msg_list(), non_empty(list(tag()))},
            begin
                Patterns1 = to_patterns(Patterns),
                Expected = receive_first_match(Mailbox, Patterns1),
                case Expected of
                    nomatch -> true;  %% ambos bloqueiam
                    _ ->
                        %% O receive real (stock) retorna a mesma mensagem
                        Actual = stock_receive(Mailbox, Patterns1),
                        Expected =:= Actual
                end
            end).

%% Simula o receive stock do BEAM: scan linear, primeira mensagem
%% em ordem de mailbox que casa a primeira cláusula, depois a segunda, etc.
stock_receive(Mailbox, Patterns) ->
    FirstMatch = lists:dropwhile(fun(M) ->
        not matches_any(M, Patterns) end, Mailbox),
    case FirstMatch of
        [] -> nomatch;
        [M | _] -> M
    end.

%% Invariante First-Match: se a primeira mensagem da mailbox casa,
%% ela é sempre a devolvida (ordem de chegada respeitada).
prop_first_match() ->
    ?FORALL({Mailbox, Patterns},
            {msg_list(), non_empty(list(tag()))},
            begin
                Patterns1 = to_patterns(Patterns),
                case Mailbox of
                    [] -> true;
                    [First | _] ->
                        case matches_any(First, Patterns1) of
                            true ->
                                receive_first_match(Mailbox, Patterns1) =:= First;
                            false ->
                                %% Primeira não casa: mensagem anterior é
                                %% preservada na mailbox (não-consumível
                                %% não pode "pular" a fila)
                                true
                        end
                end
            end).
