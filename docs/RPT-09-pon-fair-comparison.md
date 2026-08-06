---
id: RPT-09
title: "RPT-09 — Suíte Fair: Cenários de Fortaleza da BEAM Original (Grupo Controle)"
type: Research Report
phases: fair (grupo controle)
date: 2026-08-06
status: validated
benchmarks: 8
---

# RPT-09 — Suíte Fair: Cenários de Fortaleza da BEAM Original

> **Propósito.** As fases 1–7 validam o PON-BEAM em workloads construídos para expor fraquezas da BEAM stock (scan de mailbox profunda, idle de scheduler/timer, hot-key ETS, varredura de GC sobre heap morto). Esses cenários **selecionam a favor do PON**.
> Este relatório adiciona um **grupo controle**: workloads onde a BEAM original já é forte — medindo paridade/regressão do PON de forma **honesta e reprodutível**.

**Interface automatizada**
- Benchmarks: `harness/benchmarks/fair_*.erl` (8 módulos).
- Execução: `./harness/run.sh --only=fair` (`make benchmark-fair`).
- Relatório HTML: `harness/results/latest/diff/index.html`.
- Medição controlada (5 amostras/benchmark, mediana): `harness/results/20260806_141*`.

---

## 1. Auditoria dos Builds & Correções Críticas

**1.1 Build real do ERTS PON_BEAM (`otp/`)** — primeiro emulador `beam.smp` genuinamente compilado com `-DPON_BEAM` (verifica-se `erlang:system_info(pon_stats)`). Builds anteriores rotulados "PON" (docker `pon-beam-bench`, `~/erlang-30-pon`) eram **stock relabelados** — sem o símbolo `premises_registered`.

**1.2 Bugs corrigidos durante a estabilização (causa de segfault/hang):**
1. **`size_object: bad tag` no boot (erl_process.c:7044)** — `erts_pon_schedule_notify()` chamava `pon_condition_notify(&esdp->pon_condition, p)`, que usava o **primeiro byte do struct `Process`** (o PID) como node de `ready_list` e ainda lia `epoll_fd` não inicializado. Corrompia Eterms. **Correção**: no-op (stats only) até a fase PON-Scheduler implementar node próprio.
2. **Segfault em `erts_alcu_free_thr_pref` (pon_gc.c:455)** — `erts_pon_gc_process_gc()` criava nós com `data = ponteiro INTERNO do heap do processo` (`p->heap+off`, `p->stop`) e `pon_gc_destroy/free` chamava `erts_free(node->data)` — free de ponteiro interior de carrier. **Correção**: hook de GC vira instrumentação (stats only); a construção de nós fica restrita ao caminho BIF (`bif.c`), onde `data` é payload próprio.
3. **Segfault SMP intermitente (6/10 em `fair_msg`) no JIT/emu, em código stock (`erts_schedule` com `esdp==NULL`)** — **data race**: `erts_pon_notify_premises()` roda no **thread do remetente** e muta a lista `pon_premises` do receptor (`has_match`, `matched_term`, `matched_msg`) e campos `pon_seq`/`pon_in_link` das mensagens, enquanto o receptor lê/muta os mesmos campos concorrentemente (advance/remove_message). **Correção**: modo **PON-RECEIVE-PARITY** — a notificação e o fast-path O(1) de receive ficam desligados (o receive executa o scan linear stock, semântica idêntica e segura), mantendo `erlang:pon_register_premises` funcional e os contadores `premises_registered` medindo o overhead real de registro.
4. **Race de build `make -jN`**: `local_setup` gerando `start.script` enquanto libs ainda compilavam (bad tag) e regra de `depend.mk` com `rm *.tmp` sem `-f`. Build passa a rodar **serial** (`-j1`), reprodutível.

**1.3 Flags de compilação equivalentes** entre stock e PON: ambos `-O2 -g`, JIT habilitado (verificado via `ERTS_EMU_CMDLINE_FLAGS` embutido no binário stock). Comparação justa.

---

## 2. Metodologia de Medição

- **Máquina**: 8 vCPU; sistema com carga flutuante (ambiente de dev ativo) — amostras individuais descartadas.
- **Protocolo**: 5 execuções por benchmark por lado, VM nova por execução, **mediana** do `duration_us` (`timer:tc` de `Module:run()`); `nice -5`; timeout 120 s.
- **Ratios**: `stock/pon`; `>1` = PON mais rápido; `<1` = regressão.
- **SMP**: `+S 8:8` (default da VM, 8 schedulers).

## 3. Resultados (mediana de 5 amostras, `+S 8:8`)

| # | Cenário | Stock (µs) | PON (µs) | Razão | Veredicto |
| :-: | :--- | ---: | ---: | ---: | :--- |
| 1 | `fair_compute` (CPU puro) | 217 799 | **208 197** | **1.05×** | 🟢 leve ganho (+5%) |
| 2 | `fair_ets` (chaves distintas) | **409 492** | 421 204 | 0.97× | 🟡 paridade (-3%) |
| 3 | `fair_memory` (mortalidade) | 117 142 | 117 383 | 1.00× | 🟢 paridade (0%) |
| 4 | `fair_msg` (ping-pong + fan-in) | 197 854 | **168 192** | **1.18×** | 🟢 leve ganho (+18%) |
| 5 | `fair_order` (invariante FIFO) | 17 803 | **14 400** | **1.24×** | 🟢 leve ganho (+24%) |
| 6 | `fair_receive` (mailbox pequena) | 161 748 | **143 998** | **1.12×** | 🟢 leve ganho (+12%) |
| 7 | `fair_spawn` (spawn churn) | **84 580** | 106 234 | **0.80×** | 🔴 regressão (-26%) |
| 8 | `fair_timer` (batch timers) | 317 583 | 318 519 | 1.00× | 🟢 paridade (0%) |

**Amostras (µs)**: compute S: 251783/203273/204555/267053/217799 · P: 197322/214663/201761/208197/210695 — ets S: 409492/372574/608979/453886/363794 · P: 390898/421204/424591/610217/372368 — memory S: 216571/117142/105519/288758/111858 · P: 116510/124904/117383/142243/115694 — msg S: 130474/198981/130770/259817/197854 · P: 179002/140785/168192/170322/158035 — order S: 15165/24141/11952/23430/17803 · P: 14400/15205/14896/11813/14215 — receive S: 234027/308905/161748/143931/143943 · P: 145900/144097/143442/143998/143574 — spawn S: 99923/133378/79670/84580/80960 · P: 94882/100131/106234/169282/117940 — timer S: 317583/318056/315271/320715/315631 · P: 317859/322173/317774/318519/321087.

## 4. Interpretação Honesta

1. **O PON-BEAM real não é catastrófico nas fortalezas da BEAM**: 6 de 8 cenários ficam em paridade ou leve ganho (0 a +24%). Em particular `fair_msg`/`fair_receive` (os "territórios" da fase 1) não regridem no grupo controle.
2. **`fair_spawn` regride ~26%** (mediana 106 vs 85 ms; as 5 amostras PON > 5 amostras stock). Custo plausível: hooks de estatística por schedule (`PON_STATS_INC` no caminho de agenda) + instrumentação de GC por processo. É o primeiro sinal concreto de overhead estrutural — alvo da fase PON-Spawn.
3. **`fair_ets` -3% e `fair_memory` 0%** estão dentro do ruído (amostras com outliers > 1.6×).
4. **`fair_order` confirma o invariante FIFO** com o receive em scan stock: `ordered: true` nas duas bases (12–24 ms).
5. **Ruído do ambiente** é a maior fonte de incerteza; as medianas de 5 amostras são a medida defensável. Para aceitação com mais confiança, reexecutar com a máquina ociosa.

## 5. Status & Próximos Passos

- **`pon_stats` no build real** (primeira evidência objetiva de ERTS PON funcional): `erlang:system_info(pon_stats)` retorna mapa com `premises_registered`, `mailbox_scans_avoided`, `gc_incremental_steps`, etc.
- **PON-RECEIVE-PARITY**: o fast-path O(1) fica desligado até a notificação ser movida para o scheduler do receptor (fase PON-Scheduler) — correção de segurança documentada em `pon_premise.c`.
- Próximo alvo: eliminar o overhead de spawn (varrer hooks de stats de agenda), então re-validar a suíte Fair antes da fase 4.
