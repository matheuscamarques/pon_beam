# PON-BEAM — Máquina Virtual Orientada a Notificações

Uma re-arquitetura da BEAM (Erlang/OTP) usando o Paradigma Orientado a
Notificações (PON) de Jean Marcelo Simão.

## Pré-requisitos

- Erlang/OTP já instalado (para bootstrap)
- GCC / Clang
- make, autoconf, m4
- Linux (para eventfd/timerfd — essenciais para PON-Scheduler e PON-Timer)
- Graphviz (opcional, para diagramas)

## Build

```bash
# Baseline (OTP 30 stock)
make build-stock

# PON-BEAM
make build-pon

# PON-BEAM com debug (contadores)
make build-pon-debug
```

Os ERTS são instalados em `/opt/erlang/30-stock` e `/opt/erlang/30-pon`.

## Benchmark

```bash
# Harness completo (todos os benchmarks nos dois ERTS)
make benchmark

# Fase específica
make benchmark-fase1

# Listar benchmarks
make benchmark-list

# Ver relatório
make report
```

## Estrutura

```
pon-beam/
├── otp/           # Fork do OTP 30.0-rc0 (branch pon-beam)
├── harness/       # Harness de comparação (before/after)
└── docs/          # Especificações
```

## Fases

| Fase | O quê | Status |
|------|-------|--------|
| 0 | Infraestrutura | ✅ Feito |
| 1 | PON-Receive | ⏳ Pendente |
| 2 | PON-Timer | ⏳ Pendente |
| 3 | PON-Spawn | ⏳ Pendente |
| 4 | PON-Scheduler | ⏳ Pendente |
| 5 | PON-ETS | ⏳ Pendente |
| 6 | PON-Compiler | ⏳ Pendente |
| 7 | PON-GC | ⏳ Pendente |

## Licença

Apache 2.0 (mesma do Erlang/OTP)
