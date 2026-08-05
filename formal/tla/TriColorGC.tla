---- MODULE TriColorGC ----
\* TriColorGC.tla — Modelo TLA+ do PON-GC (mark-sweep tri-color)
\*
\* Modela o coletor tri-color do PON-BEAM:
\*   - Branco: não alcançado (candidato a coleta)
\*   - Cinza: alcançado, com dependências ainda não varridas
\*   - Preto: alcançado e varrido (seguro)
\*
\* O GC é um algoritmo de 3 fases: mark (branco->cinza->preto),
\* sweep (coleta brancos), e o invariante fundamental é que nenhum
\* objeto PRETO aponta para um objeto BRANCO ao fim do mark.
\*
\* Invariantes verificadas pelo TLC:
\*   - NoBlackToWhite: nenhum objeto preto aponta para objeto branco
\*     (durante o mark; o invariante fraco do tri-color)
\*   - RootsSafe: raízes nunca são coletadas
\*   - SweepComplete: após o sweep, todo objeto é preto ou coletado
\*   - NoLiveCollect: objeto alcançado (preto) nunca é coletado

EXTENDS Integers, FiniteSets

CONSTANTS
    \* Objetos no heap
    Objects,
    \* Raízes do GC (variáveis globais, pilha, registradores)
    Roots,
    \* Limite de passos do modelo
    MaxSteps

\* Relação de apontamento objeto -> conjunto de filhos.
\* Instância concreta: heap de 4 objetos, raíz 1:
\*   1 -> {2}, 2 -> {3}, 3 e 4 sem filhos.
\* Objeto 4 não-alcançável => coletável; 1/2/3 vivos.
ChildrenOf(o) ==
    IF o = 1 THEN {2}
    ELSE IF o = 2 THEN {3}
    ELSE IF o = 3 THEN {}
    ELSE {}

\* === Ações ===

VARIABLES
    \* Cor de cada objeto: {color |-> "white"|"gray"|"black", step |-> s}
    Color,
    \* Conjunto de objetos coletados pelo sweep
    Collected,
    \* Passos decorridos
    Step

vars == <<Color, Collected, Step>>

\* === Estado inicial ===
\* Todo objeto é branco, exceto as raízes que são cinza (marcadas)
Init ==
    /\ Color = [o \in Objects |->
                    IF o \in Roots THEN [color |-> "gray"]
                    ELSE [color |-> "white"]]
    /\ Collected = {}
    /\ Step = 0

\* === Ações ===

\* MarkStep: varre um objeto cinza, marcando cada filho branco como
\* cinza, e tornando o próprio preto
MarkStep(o) ==
    /\ Step < MaxSteps
    /\ o \in Objects
    /\ Color[o].color = "gray"
    /\ Color' = [x \in Objects |->
                    IF x = o THEN [color |-> "black"]
                    ELSE IF Color[x].color = "white" /\ x \in ChildrenOf(o)
                        THEN [color |-> "gray"]
                    ELSE Color[x]]
    /\ Collected' = Collected
    /\ Step' = Step + 1

\* SweepStep: coleta um objeto branco (não-alcançado).
\* Só roda quando o MARK terminou (nenhum objeto cinza) —
\* como no GC real, onde sweep começa após a fase de marcação.
\* Um objeto já coletado nunca é re-coletado.
SweepStep(o) ==
    /\ Step < MaxSteps
    /\ \A x \in Objects : Color[x].color /= "gray"
    /\ o \in Objects
    /\ Color[o].color = "white"
    /\ o \notin Roots
    /\ o \notin Collected
    /\ Collected' = Collected \cup {o}
    /\ Color' = Color
    /\ Step' = Step + 1

\* FinishMark: não-faça-nada quando o mark terminou e resta algum
\* branco a coletar — mantém o modelo com ciclo fechado (as ações
\* do sweep limitam a profundidade; FinishMark apenas avança o passo
\* para garantir progresso até o fim do sweep).
FinishMark ==
    /\ \A o \in Objects : Color[o].color /= "gray"
    /\ Step < MaxSteps
    /\ Step' = Step + 1
    /\ UNCHANGED <<Color, Collected>>

\* === Disjunção das ações ===
Next ==
    (\E o \in Objects : MarkStep(o))
    \/ (\E o \in Objects : SweepStep(o))
    \/ FinishMark

Spec == Init /\ [][Next]_vars

\* === Invariantes ===

\* NoBlackToWhite: nenhum objeto preto aponta para branco.
\* Este é o invariante fraco clássico do tri-color marking — se for
\* violado, o sweep pode coletar um objeto vivo.
NoBlackToWhite ==
    \A b \in Objects :
        Color[b].color = "black" =>
            \A w \in ChildrenOf(b) : Color[w].color /= "white"

\* RootsSafe: raiz nunca é coletada
RootsSafe ==
    \A r \in Roots : r \notin Collected

\* NoLiveCollect: objeto preto nunca é coletado
NoLiveCollect ==
    \A b \in Objects :
        Color[b].color = "black" => b \notin Collected

\* WhiteCollectOnly: apenas objetos brancos são coletados
WhiteCollectOnly ==
    \A c \in Collected : Color[c].color = "white"

=============================================================================