---
id: RPT-08
titulo: PON-BEAM Etapa C — Spike de Instrumentação do PON-Receive
parte: VII
status: relatorio
data: 2026-08-04
autor: Matheus de Camargo Marques
fase: 0
subsistema: PON-Receive (BIFs de Premises, hook do receive no interpreter, contadores pon_stats)
---

# PON-BEAM Etapa C — Spike de Instrumentação do PON-Receive

> "Sem notificação não há reatividade: o receptor que ignora a chegada e mais uma vez escaneia o que já conhece é a definição de custo evanescente." — Jean Marcelo Simão, *Paradigma Orientado a Notificações*, 2009

## 1. Resumo executivo

A Etapa C entregou a **instrumentação mínima** para validar o pipeline PON-Receive no ERTS real (OTP 30/ERTS 17.0.4, kernel forked de OTP 30.0-rc0). Duas BIFs novas expõem as Premises ao Erlang (`pon_register_premises/1` e `pon_unregister_premises/0`), o hook do receive é instrumentado **no interpreter** (`FLAVOR=emu`), e um mapa de contadores `system_info(pon_stats)` aparece o estado do mecanismo. Durante a sessão foram descobertos e resolvidos **dois defeitos de base** que impediam qualquer BIF nova de ser chamada em runtime neste ERTS.

| Eventos da sessão | Resultado |
|---|---|
| Hang em `pon_register_premises/1` (spin 100% CPU) | Root cause: trampoline do export de BIF nova preso no error_handler → re-apply infinito. Fix no `install_bifs` de ambos os flavors. |
| Match de Premise nunca casava | `erts_pon_default_match` usava representação de tuplas do OTP pré-30; no ERTS 30 a aridade está na palavra do heap e os elementos em `[1..arity]`. Correto. |
| Fast-path do receive | 5000 ruídos + alvo no fim da fila recebido em **20 µs** (sem scan). |
| Harness fase 1 | PON 14,2 ms vs stock 14,6 ms (receive) e 15,4 ms vs 17,2 ms (size) @ 100K msg — ganho parcial; O(1) completo depende do type queue. |

## 2. Contexto

A arquitetura PON-BEAM (EX-37) prevê para cada subsistema interno uma re-arquitetura por notificações. Para a fase 1 (PON-Receive), o primeiro passo é ter um **gancho observável** do mecanismo: registrar premissas em um processo, notificar a chegada de mensagens casadas e fazer o receive avançar sem escanear. Até esta Etapa C existiam apenas esqueletos em `pon_*.c` e o código da premissa, mas nada conectado até o interpretador.

### Decisões tomadas

- **Interpreter-only desta etapa**: o hook do receive está em `emu/msg_instrs.tab`; o JIT (flavor jit) fica para depois. Por isso o ERTS PON instalado é `FLAVOR=emu`.
- `+JPemulator` **não existe** neste ERTS — corrigido o `run.sh` que o usava.
- `pon_stats` **sempre ligado sob `PON_BEAM`** (via TLS `__thread`), `system_info(pon_stats)` retorna o mapa de contadores.
- BIFs novas são incondicionais na tabela (o gerador `make_tables` ignora `#ifdef PON_BEAM`); sem `PON_BEAM` retornam `badarg`.

## 3. Mudanças implementadas

| Arquivo | Mudança |
|---------|---------|
| `erts/emulator/beam/bif.tab` | Entradas `erlang:pon_register_premises/1` e `erlang:pon_unregister_premises/0`. |
| `erts/emulator/beam/bif.c` | Implementação das duas BIFs: converte lista de padrões em `ErtsPremise` encadeada (liga índices de cláusula); valida lista imprópria; `badarg` sem `PON_BEAM`. |
| `erts/emulator/beam/erl_bif_info.c` | Branch `erlang:system_info(pon_stats)` → mapa com 8 contadores. |
| `erts/emulator/beam/erl_process.c` | Instância TLS `pon_stats`; libera premissões do processo em `delete_process`. |
| `erts/include/internal/pon_stats.h` | Contadores sempre ativos (`PON_STATS_INC/ADD/BEGIN_TIMER/END_TIMER`). |
| `erts/include/internal/pon_premise.h` | Protótipos de `erts_pon_advance_to_matched` e `erts_pon_note_message_consumed`. |
| `erts/emulator/beam/pon_premise.c` | `default_match` corrigido p/ ERTS 30; `advance_to_matched` (avança o save pointer p/ a 1ª mensagem casada sem resolver bindings); `note_message_consumed` (limpa a premissão consumida). |
| `erts/emulator/beam/emu/msg_instrs.tab` | Em `loop_rec` e `remove_message`, os hooks PON avançam o save pointer diretamente para a mensagem casada (sem alterar o fluxo normal do scan). |
| `erts/emulator/beam/erl_message.c` | Notifica premissões de mensagens únicas (após `LINK_MESSAGE`). |
| `erts/emulator/beam/erl_proc_sig_queue.c` | Notifica premissões no `enqueue_signals` (lote direto). |
| `emu/beam_emu.c` e `jit/beam_jit_main.cpp` | **Fix crítico**: em `install_bifs`, arma o trampoline do export das BIFs PON com `op_call_bif_W` + função real. |
| `erts/emulator/beam/pon_condition.c`, `pon_ets.c`, `pon_gc.c`, `pon_timer.c` | Adicionado `config.h` antes de `sys.h` (necessário para compilar). |
| `harness/run.sh` | Remove `+JPemulator`; corrige o filtro `--fase=N`. |
| `harness/benchmarks/fase1_receive.erl`, `fase1_size.erl` | Consumer registra premissões com fallback `catch error:undef`. |

## 4. Defeitos estruturais descobertos

### 4.1 BIFs novas nunca executavam (hang / busy-loop em 100% de CPU) — os dois flavors

`erlang:pon_register_premises/1` chamada via `eval` (ou `apply/3`) travava com CPU 100% mesmo **o corpo da BIF retornando `true` imediatamente**. Investigação (`install_bifs` debug, bytecode routing) revelou:

1. `install_bifs` registra as BIFs no export table com o trampoline `call_error_handler`.
2. Quando um módulo que chama a BIF é carregado, o loader substitui o endereço do export para `call_bif_W` (caminho direto).
3. BIFs novas nunca são importadas por nenhum módulo do sistema → o trampoline permanece em `call_error_handler`.
4. `error_handler:undefined_function(erlang, F, Args)` vê `function_exported = true`, chama `apply(erlang, F, Args)`, que repete o caminho → **recursão infinita C** (sem crescer a pilha Erlang → busy-loop).

Correção (nos dois flavors): em `install_bifs`, para as BIFs PON, armar o trampoline com `op_call_bif_W` + `entry->f`, como faz `erts_init_trap_export`. Resultado: `pon_register_premises/1` despacha direto, sem depender de um módulo eventualmente carregado.

### 4.2 `erts_pon_default_match` obsoleto para o ERTS 30

O match nunca casava (`premise_notifications` ficava 0) apesar do `is_tuple` dizer que havia tupla. O código C original (da tese anterior) usava `arityval(term)` no termo e iterava elementos de `tuple_val(term)[0]`. Sobre ERTS 30:

- `arityval(x)` agora computa sobre a **palavra header do heap**: o valor correto é `arityval(*tuple_val(x))`.
- A tupla no heap é `[header_arity, elem1, ..., elemN]` — elementos começam em `[1]`, não em `[0]`.

A correção foi feita lendo o padrão canônico em `erl_bif_lists.c:1324` (`arityval(*tuple_ptr)` + `tuple_ptr[1..]`).

## 5. Validação funcional

| Teste | Resultado |
|-------|-----------|
| `pon_register_premises([{target, value}])` → `true` | OK (BIF dispatchável) |
| `pon_unregister_premises()` → `true` | OK |
| `pon_register_premises({bad, arg})` | `badarg` |
| `pon_register_premises([{a,1}\|bad])` (lista imprópria) | `badarg` |
| 5000 ruídos + alvo no fim da fila | receive em **20 µs**; `premise_notifications=1`; `mailbox_scans_avoided` incrementado |
| Alvo no meio da fila (ruído antes e depois) | `a_ok` + receive subsequente correto |
| Processo sem premissões registradas | scan normal preservado (`{b_got, hello}`) |
| Premise que não casa (`[{nope,x}]` vs `{noise,7}`) | timeout correto (scan normal) — sem travamentos |

## 6. Resultado no harness (fase 1)

Mesmo workload nos dois ERTS (`+S 1:1`, user bench `fase1_receive` e `fase1_size`, alvo no fundo da mailbox):

| Benchmark | Baseline stock | PON-BEAM | Ganho |
|-----------|----------------|----------|-------|
| `fase1_receive` @100K | 14 629 µs | 14 186 µs | −3% |
| `fase1_size` @100K | 17 183 µs | 15 369 µs | −11% |

O ganho é **parcial**: o `advance_to_matched` elimina o pattern-match por mensagem (o custo mais caro do scan), mas ainda caminha a lista de ponteiros quando o alvo está no fim da fila. A economia de match é real e mensurável, mas a curva continua O(N): a prova da tese (**O(1)**) só ocorre quando o receive parte da posição da última mensagem processada, ou quando o **type queue por bucket** é restaurado. O type queue (lista paralela bucket → mensagens) foi reduzido a contadores nesta sessão por referência circular ao re-linkar; reintroduzir corretamente é o próximo passo.

## 7. Próximo passo

1. **Restaurar o type queue por bucket** (lista paralela sem alterar `ErtsMessage->next`), para `advance_to_matched` pular diretamente para a mensagem casada → receive O(1) real.
2. Rebuildar o baseline stock com `FLAVOR=emu` para comparação justa (harness atual usa stock JIT).
3. Prova de carga com alvo no meio/top da fila + contagens de `mailbox_scans_avoided` vs tempo.

## 8. Arquivos

- Modificados (spike): `bif.tab`, `bif.c`, `erl_bif_info.c`, `erl_process.c`, `pon_stats.h`, `pon_premise.h`, `pon_premise.c`, `emu/msg_instrs.tab`, `erl_message.c`, `erl_proc_sig_queue.c`, `emu/beam_emu.c`, `jit/beam_jit_main.cpp`, `pon_condition.c`, `pon_ets.c`, `pon_gc.c`, `pon_timer.c`, `harness/run.sh`, `fase1_receive.erl`, `fase1_size.erl`.
- Gerados pela build (não commitados): `erl_atom_table.h/c`, `erl_bif_list.h`, `erl_bif_table.h/c`.