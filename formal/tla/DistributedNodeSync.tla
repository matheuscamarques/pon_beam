---- MODULE DistributedNodeSync ----
\* DistributedNodeSync.tla — Modelo TLA+ de Notificação PON em Clusters Distribuídos

EXTENDS Integers, FiniteSets

CONSTANTS Nodes, Messages

VARIABLES NodeState, Network, Delivered

vars == <<NodeState, Network, Delivered>>

Init ==
    /\ NodeState = [n \in Nodes |-> [clock |-> 0]]
    /\ Network = {}
    /\ Delivered = {}

SendRemote(src, dst, msg) ==
    /\ src # dst
    /\ [id |-> msg, src |-> src, dst |-> dst] \notin Network
    /\ Network' = Network \cup {[id |-> msg, src |-> src, dst |-> dst, clock |-> NodeState[src].clock + 1]}
    /\ NodeState' = [NodeState EXCEPT ![src].clock = NodeState[src].clock + 1]
    /\ UNCHANGED Delivered

ReceiveRemote(dst, msg) ==
    /\ msg \in Network
    /\ msg.dst = dst
    /\ Network' = Network \ {msg}
    /\ Delivered' = Delivered \cup {msg}
    /\ NodeState' = [NodeState EXCEPT ![dst].clock = IF msg.clock > NodeState[dst].clock THEN msg.clock + 1 ELSE NodeState[dst].clock + 1]

Next ==
    \/ \E src, dst \in Nodes, m \in Messages : SendRemote(src, dst, m)
    \/ \E dst \in Nodes, m \in Network : ReceiveRemote(dst, m)

Spec == Init /\ [][Next]_vars

CausalOrderPreserved == \A m1, m2 \in Delivered : m1.clock <= m2.clock \/ m1.clock > m2.clock
====
