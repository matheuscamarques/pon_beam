---
id: 10
titulo: "PON-Compiler: Automatic Premise Generation"
parte: II
status: completed
dificuldade: media
nota: Erlang AST parse transform (`pon_compiler.erl`) translating receive statements into NOP Premises.
fontes:
  - docs/RPT-06-pon-compiler.md
  - harness/benchmarks/lib/pon_compiler.erl
  - harness/benchmarks/lib/pon_runtime.erl
  - formal/tla/CompilerSemanticsEquivalence.tla
---

# 10. PON-Compiler: Automatic Premise Generation

> *"The compiler should not generate code that searches. It should generate code that notifies."*  
> — Matheus de Camargo Marques, 2025

---

## 10.1 Diagnosis: Traditional Compilation of `receive`

The standard Erlang compiler (`beam_ssa_recv.erl`) lowers `receive` statements into iterative `loop_rec` instructions that scan mailbox nodes linearly.

---

## 10.2 Proposal: Erlang Parse Transform (`pon_compiler.erl`)

`pon_compiler.erl` implements an AST parse transform that intercepts `receive` expressions and rewrites them into NOP Premise registration calls handled by `pon_runtime.erl`:

```erlang
%% Original code:
receive
    {msg, X} -> handle(X)
after 1000 ->
    timeout
end.

%% Transformed code (PON-Compiler):
pon_runtime:recv_premise(
    [{msg, fun(X) -> handle(X) end}],
    1000,
    fun() -> timeout end
).
```

---

## 10.3 Formal Verification

- **TLA+ Formal Model (`formal/tla/CompilerSemanticsEquivalence.tla`)**: Mathematical proof of semantic equivalence between stock SSA `loop_rec` instructions and PON-Compiler transformed Premises.

---

## 10.4 References & See Also

- [Chapter 4: PON-Receive](04-pon-receive.html)
- [Parse Transform Source `pon_compiler.erl`](file:///home/sanonichan/projetos/pon-beam/harness/benchmarks/lib/pon_compiler.erl)
