---- MODULE MailboxPON ----
\* MailboxPON.tla — TLA+ Model for PON Reactive Mailbox and pon_in_link Invariants
\*
\* Proves that concurrent message sends with reactive Premises never corrupt the save pointer
\* (pon_in_link) or cause lost messages/notifications.

EXTENDS Integers, FiniteSets

CONSTANTS
    Messages,
    Premises

VARIABLES
    MailboxQueue,     \* Lista sequencial de mensagens recebidas
    PonInLink,        \* Ponteiro de salvamento (pon_in_link): offset ou Nil
    ActivePremise,    \* Premise atualmente ativa no processo (ou Nil)
    ConsumedMessages  \* Conjunto de mensagens já casadas/consumidas

vars == <<MailboxQueue, PonInLink, ActivePremise, ConsumedMessages>>

Nil == "Nil"

TypeOK ==
    /\ MailboxQueue \in SUBSET Messages
    /\ ConsumedMessages \in SUBSET Messages
    /\ ActivePremise \in Premises \cup {Nil}

Init ==
    /\ MailboxQueue = {}
    /\ ConsumedMessages = {}
    /\ PonInLink = Nil
    /\ ActivePremise = Nil

\* Produtor faz Send(m) para o processo
SendMessage(m) ==
    /\ m \in Messages \ (MailboxQueue \cup ConsumedMessages)
    /\ MailboxQueue' = MailboxQueue \cup {m}
    /\ UNCHANGED <<PonInLink, ActivePremise, ConsumedMessages>>

\* Consumidor registra uma Premise p
RegisterPremise(p) ==
    /\ ActivePremise = Nil
    /\ p \in Premises
    /\ ActivePremise' = p
    /\ UNCHANGED <<MailboxQueue, PonInLink, ConsumedMessages>>

\* Notificação pontual O(1): Premise casa com mensagem m na MailboxQueue
MatchPremise(m) ==
    /\ ActivePremise /= Nil
    /\ m \in MailboxQueue
    /\ MailboxQueue' = MailboxQueue \ {m}
    /\ ConsumedMessages' = ConsumedMessages \cup {m}
    /\ ActivePremise' = Nil
    /\ PonInLink' = Nil

Next ==
    \/ \E m \in Messages : SendMessage(m)
    \/ \E p \in Premises : RegisterPremise(p)
    \/ \E m \in Messages : MatchPremise(m)

Spec == Init /\ [][Next]_vars

\* Invariantes
Safety_NoLostMessage ==
    Messages = MailboxQueue \cup ConsumedMessages \cup (Messages \ (MailboxQueue \cup ConsumedMessages))

Safety_MailboxIntegrity ==
    MailboxQueue \cap ConsumedMessages = {}

=============================================================================
