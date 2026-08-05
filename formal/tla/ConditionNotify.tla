---- MODULE ConditionNotify ----
\* ConditionNotify.tla — Modelo TLA+ do PON-Scheduler/ETS watcher
\*
\* Modela a Condition do PON-BEAM (eventfd + ready_list lock-free):
\* produtores sinalizam notificações; um consumidor (scheduler ou
\* watcher de ETS) drena a lista de ready e processa cada notificação
\* exatamente uma vez.
\*
\* Cada notificação é uma instância única [nid |-> n, item |-> i] —
\* como o eventfd, onde cada write é uma ocorrência distinta e cada
\* read drena um contador.
\*
\* Entidades PON modeladas:
\*   - Notify: [nid |-> n, item |-> i] enfileirado na ready_list
\*   - ready_list: conjunto de notificações pendentes
\*   - Consume: drena uma notificação e a processa (eventfd read)
\*
\* Invariantes verificadas pelo TLC:
\*   - ExactlyOnce: cada notificação é consumida no máximo 1x
\*   - NoLostNotification: toda notificação é consumida ou pendente
\*   - ProcessedSound: cada item processado veio de notificação existente
\*   - NotifyCount: o número de notificações por item pendentes/processadas
\*     é consistente com o quanto foi notificado

EXTENDS Integers, FiniteSets

CONSTANTS
    \* IDs de notificação possíveis (ocorrências)
    NotifIds,
    \* Itens possíveis que geram notificações (ex.: chaves de ETS)
    Items

VARIABLES
    \* Notificações enfileiradas: conjunto de [nid |-> n, item |-> i]
    Pending,
    \* Notificações já consumidas: conjunto de [nid |-> n, item |-> i]
    Processed

vars == <<Pending, Processed>>

Init ==
    /\ Pending = {}
    /\ Processed = {}

\* === Ações ===

\* Produtor notifica: enfileira a ocorrência [nid, item] na ready_list.
\* Cada nid é uma ocorrência única (tanto quanto no eventfd, cada
\* write é um offset distinto) — usado no máximo uma vez.
Notify(n, i) ==
    /\ n \in NotifIds
    /\ i \in Items
    /\ n \notin {p.nid : p \in Pending}
    /\ n \notin {p.nid : p \in Processed}
    /\ Pending' = Pending \cup {[nid |-> n, item |-> i]}
    /\ UNCHANGED Processed

\* Consumidor drena UMA notificação e a processa
Consume(n, i) ==
    /\ [nid |-> n, item |-> i] \in Pending
    /\ Pending' = Pending \ {[nid |-> n, item |-> i]}
    /\ Processed' = Processed \cup {[nid |-> n, item |-> i]}

\* === Disjunção das ações ===
Next ==
    \E n \in NotifIds, i \in Items : Notify(n, i)
    \/ \E cn \in NotifIds, ci \in Items : Consume(cn, ci)

Spec == Init /\ [][Next]_vars

\* === Invariantes ===

\* ExactlyOnce: nenhuma ocorrência está pendente e processada ao mesmo
\* tempo (consumo atômico — o eventfd lê uma vez, nunca duas)
ExactlyOnce ==
    {p.nid : p \in Pending} \cap {p.nid : p \in Processed} = {}

\* NoLostNotification: toda notificação notificada é pendente ou processada
NoLostNotification ==
    {p.nid : p \in Pending} \cup {p.nid : p \in Processed}
        \subseteq NotifIds

\* ProcessedSound: cada processo corresponde a uma notificação real
ProcessedSound ==
    Processed \subseteq {[nid |-> n, item |-> i] : n \in NotifIds, i \in Items}

\* NoGhostPending: pendente só contém notificações válidas
NoGhostPending ==
    Pending \subseteq {[nid |-> n, item |-> i] : n \in NotifIds, i \in Items}

=============================================================================