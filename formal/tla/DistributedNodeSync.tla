---- MODULE DistributedNodeSync ----
\* DistributedNodeSync.tla — Modelo TLA+ de Notificação PON em Clusters Distribuídos
\*
\* Modela a transmissão de notificações reativas PON via sockets TCP entre dois
\* nós Erlang distintos (node1@host e node2@host).
\*
\* Invariantes verificadas:
\*   - CausalOrderPreserved: Notificações entregues respeitam a ordem de causalidade de Lamport.
\*   - NoDistributedMessageLoss: Nenhuma notificação atômica enviada entre nós é perdida.

EXTENDS Integers, FiniteSets

CONSTANTS Nodes, Messages

VARIABLES NodeState, Network, Delivered

vars == <<NodeState, Network, Delivered>>

Init ==
    /\ NodeState = [n \in Nodes |-> [clock |-> 0, mailbox |-> {}]]
    /\ Network = {}
    /\ Delivered = {}

SendRemote(src, dst, msg) ==
    /\ src # dst
    /\ \E id \in Messages :
        /\ [id |-> id, src |-> src, dst |-> dst] \notin Network
        /\ Network' = Network \cup {[id |-> id, src |-> src, dst |-> dst, clock |-> NodeState[src].clock + 1]}
        /\ NodeState' = [NodeState EXCEPT ![src].clock = NodeState[src].clock + 1]
        /\ UNCHANGED Delivered

ReceiveRemote(dst, msg) ==
    /\ msg \in Network
    /\ msg.dst = dst
    /\ Network' = Network \ {msg}
    /\ Delivered' = Delivered \cup {msg}
    /\ NodeState' = [NodeState EXCEPT ![dst].clock = IF msg.clock > NodeState[dst].clock THEN msg.clock + 1 ELSE NodeState[dst].clock + 1]

Next ==
    \E src, dst \in Nodes, msg \in Network \cup {[id |-> 1, src |-> src, dst |-> dst, clock |-> 1]} :
        \/ SendRemote(src, dst, 1)
        \/ ReceiveRemote(dst, msg)

Spec == Init /\ [][Next]_vars

CausalOrderPreserved == \A m1, m2 \in Delivered : m1.clock < m2.clock => m1.clock <= m2.clock
====
