---
id: RPT-06
titulo: PON-BEAM Fase 6 — Relatório de Implementação: PON-Compiler
parte: VI
status: relatorio
data: 2026-08-03
autor: Matheus de Camargo Marques
fase: 6
subsistema: PON-Compiler (parse transform para gerar Premises de receives)
---

# PON-BEAM Fase 6 — PON-Compiler: Relatório de Implementação

> "Um compilador que entende notificações pode gerar código que não percorre listas." — Adaptado de John McCarthy, *Lisp 1.5 Programmer's Manual*, 1962

## 1. Resumo executivo

A Fase 6 implementou o **PON-Compiler**: um parse transform para Erlang que converte blocos `receive` em código que registra Premises e usa `pon_runtime` para recebimento baseado em notificação, em vez de scanning linear da mailbox.

| Componente | Descrição | Linhas |
|-----------|-----------|--------|
| `pon_compiler.erl` | Parse transform: receive → Premises | 175 |
| `pon_runtime.erl` | Runtime: register_premises, receive_msg, match | 92 |

## 2. Arquitetura

### 2.1 Parse transform

```dot Fluxo do pon_compiler
digraph compiler_flow {
  rankdir=LR;
  splines=ortho

  "Cdigo fonte\ncom receive" -> "pon_compiler\n(parse transform)"
  -> "Cdigo transformado\ncom register_premises\n+ receive_msg"
  -> "Compilador\nErlang" -> "Bytecode .beam"
  -> "Runtime\n(pon_runtime)"
}
```

### 2.2 Transformação

**Antes (código Erlang original):**
```erlang
handle(Msg) ->
    receive
        {call, From, Req} -> From ! {reply, Req}, handle(Msg);
        {cast, Msg}       -> {noreply, Msg};
        Other             -> {info, Other}
    end.
```

**Depois (código transformado):**
```erlang
handle(Msg) ->
    pon_runtime:register_premises([
        {{call, '_', '_'}, true, 0},
        {{cast, '_'},      true, 1},
        {'_',              true, 2}
    ]),
    Msg1 = pon_runtime:receive_msg(),
    %% Dispatch baseado na mensagem recebida
    %% ...
    pon_runtime:unregister_premises(),
    ok.
```

### 2.3 Runtime

O módulo `pon_runtime` fornece as funções necessárias para o código transformado:

| Função | Descrição |
|--------|-----------|
| `register_premises(Patterns)` | Registra Premises no dicionário do processo |
| `receive_msg()` | Aguarda mensagem que casa alguma Premise |
| `receive_msg_timeout(TimeoutMs)` | Com timeout |
| `unregister_premises()` | Limpa Premises do dicionário |

## 3. Modificações

### 3.1 Arquivos criados

| Arquivo | Linhas | Função |
|---------|--------|--------|
| `harness/benchmarks/lib/pon_compiler.erl` | 175 | Parse transform: receive → Premises |
| `harness/benchmarks/lib/pon_runtime.erl` | 92 | Runtime: Premises + receive_msg + match |

### 3.2 Benchmarks

| Benchmark | Medição |
|-----------|---------|
| `compile_receive.erl` | Tempo de compilação de módulo com receives, com/sem PON |

## 4. Verificação

- [x] `pon_compiler.erl` — parse transform que detecta `receive` e gera código PON
- [x] `pon_runtime.erl` — runtime com register_premises, receive_msg, match
- [x] Suporta receives com e sem `after`
- [x] Suporta patterns aninhados (tuplas, listas, átomos, wildcards)
- [x] Cleanup automático via `unregister_premises`
- [x] Benchmark `compile_receive.erl`

## 5. Observações

### 5.1 Parse transform vs modificação do beam_ssa

A escolha por parse transform (em vez de modificar `beam_ssa_recv.erl`) foi pragmática:

- **Parse transform**: funciona em qualquer versão do Erlang, sem modificar o compilador
- **Modificação do beam_ssa**: mais eficiente (ótimo em SSA) mas dependente da versão do OTP e requer modificação de ~1000 linhas de código existente
- **Futuro**: a integração nativa no beam_ssa será feita quando o PON-BEAM estiver maduro

### 5.2 Limitação: match em Erlang puro

O `pon_runtime` implementa matching em Erlang puro, não em C. Isso é mais lento que o pattern matching nativo da BEAM. A otimização real vem de:
1. Eliminar o scanning da mailbox (o custo dominante em receives com mailbox lotada)
2. No futuro, implementar o matching em C (como parte do core ERTS)

### 5.3 Uso

Para usar o PON-Compiler em um módulo:

```erlang
-module(my_server).
-compile({parse_transform, pon_compiler}).
-export([loop/0]).

loop() ->
    receive
        {call, From, Msg} -> From ! {ok, Msg}, loop();
        stop -> ok
    end.
```

Compilar com:
```bash
erlc +'{parse_transform, pon_compiler}' +'{d, pon_beam}' my_server.erl
```

## Ver também

- [Fases anteriores](RPT-01-pon-receive.md)
- [Plano de engenharia](EX-38-pon-beam-plano-de-engenharia.md)
- [Capítulo 20 — O compilador Erlang](../chapters/20-o-compilador-erlang-de-ponta-a-ponta.md)
- [Código: pon_compiler.erl](../../harness/benchmarks/lib/pon_compiler.erl)
- [Código: pon_runtime.erl](../../harness/benchmarks/lib/pon_runtime.erl)
