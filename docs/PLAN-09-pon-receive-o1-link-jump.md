# PLAN-09 — PON-Receive: O(1) Real no `advance_to_matched` via `pon_in_link`

## 1. Objetivo

Fase 1 (PON-Receive), etapa D: tornar o posicionamento do `save` pointer no
`receive` **verdadeiramente O(1)**, provando a tese "scan de mailbox não escala".

Hoje o `erts_pon_advance_to_matched` (chamado no loop_rec quando há Premise com
match) ainda anda a fila com chase de ponteiro (`cur = cur->next`) até a mensagem
casada. Isso é O(distância) — mede ~159–223 µs com N=5000 de ruído. A meta é
`qs->save = m->pon_in_link` direto — O(1) — validando a curva latency vs N ~
constante.

## 2. Baseline validado (não mexer)

- Commit `157d3a1` (Etapa C) é o baseline bom:
  - `pon_fastpath_test2` N=5000 → 20 µs, N=10 → 4 µs (advance por chase).
  - Harness fase1: PON 14.2/15.4 ms vs stock 14.6/17.2 ms @ 100K.
- O `advance_to_matched` atual (fallback linear com `erts_msgq_set_save_next`) é
  **semanticamente correto** — verificado com hook e O(1) desligados (sobra o
  fallback): N=5000 passa (223 µs), N=10 (4 µs).

## 3. Design do O(1): `pon_in_link` (link de entrada)

- Campo `ErtsMessage **pon_in_link` em `struct erl_mesg` (sob `#ifdef PON_BEAM`):
  aponta para o endereço do ponteiro da fila interna que aponta PARA a mensagem
  (o campo `next` do antecessor; `&sig_qs.last` para a cabeça).
- Gravado no **fetch** (`erts_proc_sig_fetch__`), ao mover `sig_inq` → fila
  interna: caminha a cadeia com `pon_cell = &pon_mp->next` e guarda
  `pon_mp->pon_in_link = pon_cell`. Termina quando `&pon_mp->next == sig_inq.last`.
- No advance: se `m->pon_in_link && *m->pon_in_link == m` (validado — a mensagem
  ainda está na mesma célula), `qs->save = m->pon_in_link` → O(1).
- Caso contrário (fila do meio/prio/recv markers) → fallback linear atual, que
  restaura `save` e limpa a Premise se a mensagem não estiver à frente.

## 4. Bug 1 — encontrado e corrigido

`PON_INIT_MESSAGE_INTERNAL` dentro de `ERTS_INIT_MESSAGE` gravava `pon_in_link`
**também em mensagens `sz == 0`** — corrigido pela movimentação do campo para
`ERL_MESSAGE_REF_FIELDS__` (§7), voltando o init seguro via `ERTS_INIT_MESSAGE`.

## 5. Descoberta crítica (debug)

Todos os `{noise, I}` de `!` cross-process chegam no `sig_inq` do receptor como
**`ErtsMessageRef` (sz == 0, 40 bytes, stride 0x28) com `data.attached == NULL`**
— o termo mora no heap do SENDER (on-heap message), sem hfrag próprio.

Consequência resolvida: refs agora têm `pon_in_link` (§7) e o guard por `attached`
foi removido — o hook/e fazer grava o campo de todo sinal com segurança.

## 6. Bug 2 — CORRUPÇÃO EM ESCALA (CAUSA RAIZ ENCONTRADA E FIXADA)

- Sintomas: N=5000 com hook ativo → SIGSEGV; localização varia (rbt_insert,
  `erts_proc_sig_decode_dist`, mailbox apontando para stack). N=10 passa.
- **Causa raiz**: `erts_try_alloc_message_on_heap` cria o trabalho on-heap como
  `ErtsMessageRef` de 40 B, e o caminho `in_message_fragment` usa ref com
  `data.heap_frag = bp` → `attached != 0`, mas o objeto **continua sendo um ref**
  de 40 B **sem o campo** `pon_in_link`. O guard antigo `if (pon_mp->data.attached)`
  gravava `pon_in_link` 8 B além do fim do ref → corrupção do pool
  (`ERTS_ALC_T_MSG_REF`) → SIGSEGV assim que o sender lotava o heap (N≈5000).
- **Fix definitivo**: `pon_in_link` movido para dentro de `ERL_MESSAGE_REF_FIELDS__`
  via `PON_MESSAGE_REF_FIELDS__` (§7) — o campo existe em `ErtsMessage` e
  `ErtsMessageRef`; o pool fixed-size se ajusta via `sizeof`.

## 7. Alinhamento de tipos — RESOLVIDO

`PON_MESSAGE_REF_FIELDS__` (`, ErtsMessage **pon_in_link` sob `#ifdef PON_BEAM`)
inserido no fim de `ERL_MESSAGE_REF_FIELDS__` (`erl_message.h` ~233). Compartilhado
por `ErtsMessage` e `ErtsMessageRef`:
- `PON_INIT_MESSAGE(MP)` de volta dentro de `ERTS_INIT_MESSAGE` (seguro no toggle);
- refs têm o campo → o registro de link vale para todo sinal;
- `struct erl_mesg` = `ERL_MESSAGE_REF_FIELDS__` + `hfrag` (sem campo extra).

## 8. Implementação LAZY (design atual no working tree)

**Registro do `pon_in_link`** com custo **O(1) por cadeia** (não por mensagem):
1. `LINK_MESSAGE` (`erl_message.h`): `ERTS_PON_SET_IN_LINK(p,msg)` — append de
   mensagem única → cell = `sig_inq.last` (só o próprio msg).
2. `enqueue_signals` (`erl_proc_sig_queue.c` ~912, guard `!is_to_buffer`):
   **apenas a cabeça** da cadeia recebe `pon_in_link = this`.
3. `proc_sig_queue_flush_buffer` e `flush_and_deinstall_buffers` (~10557/10672):
   **apenas a cabeça** de cada chunk do buffer recebe `proc->sig_inq.last`
   (a célula do concat — escrita fora da janela do receive).
4. **Preenchimento lazy no fallback** (`erts_pon_advance_to_matched`,
   `pon_premise.c` ~231): quando o O(1) não dispara (mensagem sem célula), o
   walk do fallback grava `cur->pon_in_link = qs->save` para cada mensagem
   até o alvo — a 1ª varredura de uma região custa O(distância), as seguintes
   saltam O(1). No caso `!cur` (Premise obsoleta) o save é restaurado; as
   células gravadas durante o walk parcial permanecem válidas (apontavam para
   posições corretas).
- Advance O(1) (guard `m && m->pon_in_link && *m->pon_in_link == m && !cont &&
  !prio flags && !recv_mrk_blk`) inalterado. `PON_MESSAGE_REF_FIELDS__`
  (campo em `ErtsMessage` e `ErtsMessageRef`) e `ERTS_PON_SET_IN_LINK` também.

**Vantagem**: enqueue multi-mensagem é O(1) (antes O(chain) por batch) — tira o
custo por mensagem do lado do envio/flush; troca por uma 1ª varredura amortizada.

## 8a. Pontos de falha testados (build lazy, `+S 1:1`) — resultado

Teste `pon_lazy_test` (`/tmp/opencode/pon_lazy_test.erl`):

| Cenário | Resultado | Veredito |
|---------|-----------|----------|
| A: alvo no meio de cadeia multi-msg (20k) — 1º scan | 6 µs (fallback preenche cells) | OK |
| A: 2º scan (alvo já varrido, célula preenchida) | 1 µs (O(1)) | OK — amortiza |
| B: prioridade alta + PON (20k) | sem crash, alvo entregue | OK |
| C: receive sem catch-all c/ noise | noise intacto (`message_queue_len==2`) | OK — advance não pula |
| D: stress N=100000 | scan 6 µs, **sem SIGSEGV** | OK — corrupção Etapa C não re-emerge |

Nota estrutural: alvo que chega DENTRO de um batch multi-mensagem (ex. dist,
flush de chunk) não tem célula pré-gravada → o **1º** scan é fallback O(distância);
os seguintes são O(1). Aceitável (amortizado); o critério de aceite (scan cold do
harness) mede alvo entregue como mensagem única → O(1) estrito.

## 9. Validação (registro de medições)

- **O(1) dispara**: `[pon-adv] *link == m`, advance executa uma vez por receive.
  `mailbox_scans_avoided` conta O(1) E fallback (não usar isolado).
- **Scan isolado** (consumidor sem receive durante o flood; noise unscanned no
  receive): PON `CONSUMER`=5–7 µs vs stock 4.9 ms @ N=50000 — ~700×.
  Em runs determinísticos (sem agendamento mid-flood) o stock varre O(N) e o PON
  salta O(1) — a tese "scan não escala" fica demonstrada nesse shape.
- **End-to-end** (fetch/preload nas janelas, noise já varrido): medida dominada
  por delivery/wake O(N) compartilhado + save pointer do stock; PON ~parity a
  1000–10000, vantagem ~20–25% em 5k–10k nos runs batched, ruidoso a 100k.
- **Limitações do harness `fase1_receive`**: a janela do timer inclui wake/fetch;
  e o stock **não re-vasculha** noise já varrido (save pointer) — forçar o
  scan O(N) cold exige o consumidor fora de receive na entrega.

## 9a. Benchmark de scan cold (`fase1_receive_cold`) — RESULTADO OFICIAL

Para medir o O(1) de forma determinística e repetível, novo benchmark
`harness/benchmarks/fase1_receive_cold.erl`: o consumidor faz spin em
`message_queue_len` (conta, não varre) até a entrega completa, depois entra no
receive **frio**; a janela medida é o próprio receive na consumer
(`monotonic_time`), excluindo entrega/wake. Roda na suíte via `--only=cold`.

Mediana de 7 iterações, `+S 1:1` (harness oficial), run `20260804_163923`:

| N | Baseline (µs) | PON-BEAM (µs) | Ganho |
|---|--------------:|--------------:|------:|
| 1000 | 17 | 2 | 8.5× |
| 5000 | 123 | 5 | 24.6× |
| 10000 | 253 | 5 | 50.6× |
| 25000 | 825 | 5 | 165× |
| 50000 | 1221 | 7 | 174× |

Stock: linear O(N). PON: **plano ~5 µs** (O(1)). `mailbox_scans_avoided=70`
(35 receivers × 2), 637035 mensagens classificadas. Repro­duzível (2ª corrida:
17/123/253/825/1221 vs 2/5/5/5/7).

**Metodologia**: o conta­dor `mailbox_scans_avoided` reflete saves O(1) **e**
fallback linear; o índice isolado é a latência por N acima. O ganho de ~174×
em N=50000 demonstra a tese "receive não escala"; o end-to-end
(`fase1_receive`) permanece dominado por delivery/wake.

## 9b. Resultado oficial com build LAZY (suíte completa `20260804_170541`)

Retestado após a troca para o design lazy (§8) — o critério de aceite se mantém:

| N | Baseline (µs) | PON-BEAM (µs) | Ganho |
|---|--------------:|--------------:|------:|
| 1000 | 21 | 2 | 10.5× |
| 5000 | 139 | 5 | 27.8× |
| 10000 | 289 | 5 | 57.8× |
| 25000 | 881 | 5 | 176× |
| 50000 | 1489 | 6 | 248× |

Suíte completa (baseline vs pon): `fase1_receive` 1.08× (N=10000 2.12×,
N=100000 1.14×), `fase5_ets_read` 1.84×, `fase6_compile` 1.47×, demais em
paridade/ruído. `fase1_receive_cold` confirma o O(1) do aceite. O diff report
agora renderiza a tabela por N (aninhada) para benchmarks com chave `scans`
(`pon_diff.erl`).

## 10. Próximos passos

1. Rebuild baseline stock (`make build-stock` FLAVOR=emu) e rodar o harness
   `./run.sh --only=receive` para registro do diff desta etapa.
2. Adicionar ao harness um microbenchmark de scan **cold** (consumidor busy/fora
   de receive durante o flood, deadline de relógio) para medir o O(1) do PON.
3. Commitar incremento sobre `157d3a1`:
   `feat(fase-1): advance O(1) por link de entrada (pon_in_link) — validado`.

## 11. Arquivos relevantes

- `otp/erts/emulator/beam/erl_message.h`: `PON_MESSAGE_REF_FIELDS__` (~233),
  `struct erl_mesg`, `ERTS_INIT_MESSAGE`/`PON_INIT_MESSAGE` (~571), `LINK_MESSAGE`
  com `ERTS_PON_SET_IN_LINK` (~534).
- `otp/erts/emulator/beam/erl_proc_sig_queue.c`: `enqueue_signals` (~912),
  `proc_sig_queue_flush_buffer` (~10577) + `flush_and_deinstall_buffers`
  (~10690), splice do fetch (sem walk).
- `otp/erts/emulator/beam/pon_premise.c`: `erts_pon_advance_to_matched` (231;
  O(1) ativo), `erts_pon_note_message_consumed` (298).
- `erl_message.c`: notify das Premises (~470), `erts_try_alloc_message_on_heap`
  (~639, origem das refs on-heap/fragment).
- Testes: `/tmp/opencode/mini8.erl` (scan cold, shape isolado), `mini5.erl`
  (batched), `pon_fastpath_test2.erl` (stats), `runstock.sh`/`rpon.sh` (beam.smp
  direto com ROOTDIR/BINDIR).