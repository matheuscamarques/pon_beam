# AGENTS.md — PON-BEAM Loop de Trabalho

## Propósito

Construir a PON-BEAM: uma re-arquitetura da máquina virtual BEAM usando o
Paradigma Orientado a Notificações (PON) de Jean Marcelo Simão. Cada subsistema
interno da VM é redesenhado como entidade PON reativa — sem polling, sem scanning
linear, apenas notificações pontuais.

## Estrutura do repositório

```
pon-beam/
├── otp/                          # Fork do OTP 30.0-rc0
│   └── erts/emulator/beam/      # ERTS — onde as modificações vivem
├── harness/                      # Benchmark harness comparativo
│   ├── config/                   # Paths dos ERTS (baseline.sh, ponbeam.sh)
│   ├── benchmarks/               # Benchmarks Erlang
│   │   └── lib/                  # Módulos base (pon_harness, pon_diff, pon_stats_reader)
│   ├── report/                   # Template e assets do diff report
│   └── run.sh                    # Script principal do harness
├── docs/                         # Planos e especificações
├── Makefile                      # Build e benchmark targets
└── AGENTS.md                     # Este arquivo
```

## Branch strategy

- `otp-30.0-rc0-stock` — Código OTP original, imutável. Nunca modificar.
- `pon-beam` — Branch de trabalho. Onde as modificações PON são aplicadas.

## Fases de implementação

Cada fase é um ciclo completo: modificar ERTS → compilar → rodar benchmark →
gerar diff → commitar.

| Fase | O quê | Arquivos | Duração estimada | Critério de aceite |
|------|-------|----------|------------------|---------------------|
| 0 | Infraestrutura do fork | Makefile.in, configure.ac, pon_*.h | 1-2 semanas | `make TYPE=ponbeam` produz `beam.ponbeam.smp` funcional |
| 1 | PON-Receive | erl_message.h, erl_process.c, pon_premise.h | 4 semanas | `receive_mailbox_scan` mostra O(1) |
| 2 | PON-Timer | erl_timer.c, pon_instigation.h | 2 semanas | `timer_idle_cpu` mostra 0% CPU idle |
| 3 | PON-Spawn | erl_process.c | 1 semana | spawn_latency reduzida |
| 4 | PON-Scheduler | erl_process.c, erl_sched.h, pon_condition.h | 6 semanas | `sched_idle_cpu` mostra 0% CPU idle |
| 5 | PON-ETS | erl_db.c, erl_db.h | 6 semanas | `ets_read_repeat` mostra ~1000× |
| 6 | PON-Compiler | beam_ssa.erl, beam_opcodes.tab | 4 semanas | receives compilam para Premises |
| 7 | PON-GC | erl_gc.c, erl_gc.h | 8 semanas | `gc_heap_scan` mostra ~10× |

## Regras de ouro

1. **Nunca modificar o baseline.** O código OTP original fica em
   `otp-30.0-rc0-stock`. Toda modificação é na branch `pon-beam`.
2. **Cada modificação envolta em `#ifdef PON_BEAM`.** O código original
   permanece intacto. A PON-BEAM é uma sobreposição compilável.
3. **Toda fase entrega um diff.** Sem diff comprovando ganho, a fase não
   está completa. O harness gera automaticamente o diff HTML.
4. **Benchmark antes de modificar, benchmark depois.** Medir sempre nos
   dois ERTS com o mesmo workload.
5. **Um commit por fase.** Mensagem: `feat(fase-N): <descrição> — validado`.

## Comandos

| Comando | Ação |
|---------|------|
| `make build-stock` | Compila OTP 30 stock (baseline) |
| `make build-pon` | Compila OTP com PON-BEAM |
| `make build-pon-debug` | Compila PON-BEAM com contadores de debug |
| `make benchmark` | Roda harness completo |
| `make benchmark-fase1` | Roda benchmarks da fase 1 |
| `make benchmark-list` | Lista benchmarks disponíveis |
| `make report` | Abre último diff report |
| `make clean` | Limpa artefatos de build |

## Referências

- Tese PON-BEAM: `docs/extras/EX-37-pon-beam-arquitetura-orientada-a-notificacoes.md`
- Plano de engenharia: `docs/extras/EX-38-pon-beam-plano-de-engenharia.md`
- Paradigma Orientado a Notificações: Simão & Stadzisz (2008–2009)
