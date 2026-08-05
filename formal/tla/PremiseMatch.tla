---- MODULE PremiseMatch ----
\* PremiseMatch.tla — Modelo TLA+ do PON-Receive
\*
\* Modela a mailbox de 256 buckets do PON-BEAM com Premises.
\* Um processo envia mensagens; um Premise registrado com um pattern
\* é satisfeito quando existe uma mensagem compatível na mailbox.
\*
\* Entidades PON modeladas:
\*   - Premise: pattern registrado pelo processo consumidor
\*   - Mailbox: sacola de mensagens pendentes (representação simplificada)
\*   - Instigação: o Send notifica o Premise casável (modelado implicitamente)
\*
\* Mensagens são instâncias únicas [id |-> i, term |-> t], como na mailbox
\* real (dois sends do mesmo termo geram duas mensagens distintas).
\*
\* Invariantes verificadas pelo TLC:
\*   - PremiseSound: toda mensagem consumida casava a Premise consumidora
\*   - NoMessageLoss: toda mensagem enviada chega ou está na mailbox
\*   - NoDuplicateConsumption: mensagem consumida não volta à mailbox

EXTENDS Integers, FiniteSets

CONSTANTS
    \* Conjunto de IDs de mensagens possíveis (modelo finito)
    Ids,
    \* Conjunto de patterns suportados pelas Premises
    Patterns,
    \* Conjunto de termos que podem ser enviados como mensagem
    Terms

VARIABLES
    \* Mailbox: conjunto de mensagens pendentes [id |-> i, term |-> t]
    Mailbox,
    \* Premises: conjunto de Premises registradas
    Premises,
    \* Mensagens consumidas: [id |-> i, m |-> t, p |-> Premise]
    Received,
    \* Mensagens já enviadas pelo produtor
    Sent

vars == <<Mailbox, Premises, Received, Sent>>

\* Mensagens com mesmo id são idênticas (cada id usado no máx. uma vez)
MsgId(m) == m.id
MsgTerm(m) == m.term

\* Estado inicial: nada enviado, mailbox vazia, sem Premises
Init ==
    /\ Mailbox = {}
    /\ Premises = {}
    /\ Received = {}
    /\ Sent = {}

\* === Ações ===

\* Envia um termo para a mailbox com um id novo
\* (no PON real, o send é uma Instigação para o Premise matching)
SendMsg(id, t) ==
    /\ id \in Ids
    /\ t \in Terms
    /\ id \notin {m.id : m \in Sent}
    /\ Mailbox' = Mailbox \cup {[id |-> id, term |-> t]}
    /\ Sent' = Sent \cup {[id |-> id, term |-> t]}
    /\ UNCHANGED <<Premises, Received>>

\* Registra uma nova Premise com um pattern
RegisterPremise(p) ==
    /\ p \in Patterns
    /\ p \notin Premises
    /\ Premises' = Premises \cup {p}
    /\ UNCHANGED <<Mailbox, Received, Sent>>

\* === MatchPattern: predicado de compatibilidade pattern-termo ===
\* Padrão concreto de premência: pattern "ping" casa qualquer termo
\* que seja "ping" ou "ping-payload".
MatchPattern(p, t) ==
    (p = "ping" /\ (t = "ping" \/ t = "ping-payload"))
    \/ (p = "pong" /\ t = "pong-payload")

\* Receive: consome uma mensagem que casa uma Premise.
\* O record [id |-> i, m |-> t, p |-> prem] registra qual Premise consumiu.
Receive(p, msg) ==
    /\ p \in Premises
    /\ msg \in Mailbox
    /\ MatchPattern(p, MsgTerm(msg))
    /\ Mailbox' = Mailbox \ {msg}
    /\ Received' = Received \cup {[id |-> MsgId(msg), m |-> MsgTerm(msg), p |-> p]}
    /\ UNCHANGED <<Premises, Sent>>

\* === Disjunção das ações ===
Next ==
    \E id \in Ids, t \in Terms : SendMsg(id, t)
    \/ \E pat \in Patterns : RegisterPremise(pat)
    \/ \E prem \in Premises, msg \in Mailbox : Receive(prem, msg)

Spec == Init /\ [][Next]_vars

\* === Invariantes ===

\* PremiseSound: se o receive consumiu uma mensagem, essa mensagem
\* casava a Premise que a consumiu (a notificação PON é fiel ao
\* matching do BEAM). Sem isso, premiações errôneas consumiriam
\* mensagens incompatíveis.
PremiseSound ==
    \A r \in Received : MatchPattern(r.p, r.m)

\* NoMessageLoss: toda mensagem enviada é consumida ou está na mailbox.
\* (No PON real, se o processo morre a mensagem pode ser perdida — isso é
\*  coberto pelo modelo do GC; aqui assumimos processos vivos.)
NoMessageLoss ==
    {m.id : m \in Sent} \subseteq ({r.id : r \in Received} \cup {m.id : m \in Mailbox})

\* NoDuplicateConsumption: uma mensagem consumida não volta para a mailbox.
NoDuplicateConsumption ==
    {r.id : r \in Received} \cap {m.id : m \in Mailbox} = {}

=============================================================================
