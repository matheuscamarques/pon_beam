---
id: 20
title: "The End-to-End Erlang Compiler & SSA Pass Architecture"
part: I
status: validated
sources:
  - otp/lib/compiler/src/compile.erl
  - otp/lib/compiler/src/beam_ssa.erl
---

# The End-to-End Erlang Compiler & SSA Pass Architecture

The Erlang compiler converts source code into `.beam` bytecode via intermediate representations: AST $\to$ Core Erlang $\to$ SSA $\to$ BEAM Assembly.
