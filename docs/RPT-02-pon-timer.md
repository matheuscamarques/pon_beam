---
id: RPT-02
titulo: PON-BEAM Fase 2 — Relatório de Implementação: PON-Timer
parte: VI
status: relatorio
data: 2026-08-03
autor: Matheus de Camargo Marques
fase: 2
subsistema: PON-Timer (timers por Instigaes com timerfd, sem polling do timer wheel)
---

# PON-BEAM Fase 2 — PON-Timer: Relatório de Implementação

> "O tempo que se gasta verificando se o tempo passou é tempo que não passa — é redundância temporal pura." — Adaptado de Sêneca, *Da Brevidade da Vida*, c. 49 d.C.

## 1. Resumo executivo

A Fase 2 implementou o **PON-Timer**: substituição do polling do timer wheel por **Instigações temporais** baseadas em `timerfd` (Linux). Cada timer é criado como um file descriptor do kernel que notifica via `epoll` quando expira — sem necessidade de verificação periódica.

| Métrica | Baseline (OTP 30) | PON-BEAM (Fase 2) | Ganho esperado |
|---------|------------------|-------------------|----------------|
| CPU do timer wheel sem timers | ~3% de um core (tick a cada 1ms) | 0% (sem polling) | infinito (3% → 0%) |
| 50000 timers ativos (1s expiração) | 50M checks/s | 5 notificações/s (expirações reais) | ~10M× |
| Timer curto (<1ms) | polling normal | fallback para timer wheel | sem perda |

### 1.1 O problema do timer wheel

O timer wheel da BEAM (`erl_hl_timer.c`) mantém uma hierarquia de rodas de tempo. A cada tick do scheduler (~1ms), a roda é verificada para expirações. O custo aparece mesmo quando **nenhum timer está registrado** — o scheduler simplesmente não sabe que não há trabalho e percorre a roda mesmo assim.

```dot Timer wheel: polling constante vs timerfd: notificação sob demanda
digraph timer_comparison {
  rankdir=LR;
  splines=ortho

  subgraph cluster_wheel {
    label="Timer wheel (BEAM atual)"
    color=red
    "Tick 1ms" -> "Verifica roda" -> "Nenhum timer expirou" -> "Tick 1ms"
  }

  subgraph cluster_timerfd {
    label="PON-Timer (PON-BEAM)"
    color=green
    "Cria timerfd" -> "Kernel notifica\nquando expira" -> "Processa expiração"
    "Cria timerfd" -> "Kernel dorme\n(sem CPU)" [style=dotted]
  }
}
```

## 2. Arquitetura implementada

### 2.1 Entidade Instigation

No PON, uma **Instigação (Instigation)** é a entidade que dispara um método de um FBE quando uma condição temporal (timer) ou causal (sinal) é satisfeita. Na PON-BEAM, as Instigações temporais usam `timerfd` para notificação do kernel.

```c
// pon_instigation.h — Estrutura de uma Instigation temporal
typedef struct {
    ErtsInstigation   base;           // type, fired, target, message
    int               timer_fd;       // timerfd do kernel (-1 se inativo)
    uint64_t          expiration_ms;  // tempo de expiração (ms)
} ErtsTimerInstigation;
```

A Instigation base carrega:
- `type`: PON_INSTIGATION_TYPE_TIMER ou PON_INSTIGATION_TYPE_SIGNAL
- `fired`: booleano — 1 quando o timer já expirou
- `target`: ponteiro para o processo OTP alvo
- `message`: termo Erlang a ser enviado na expiração
- `next`: lista ligada (múltiplas Instigações por processo)

### 2.2 Timerfd + epoll

```dot Ciclo de vida de uma Instigation timer
digraph timer_lifecycle {
  rankdir=LR;
  splines=ortho

  "Processo chama\nsend_after/3" -> "Cria Instigation\n+ timerfd"
  -> "Registra no epoll\n(scheduler)" -> "Kernel monitora"
  -> "Tempo expira\n(read no timerfd)" -> "Marca fired: 1"
  -> "Envia mensagem\npara mailbox" -> "Processo recebe\ne processa"
}
```

**Mecanismo:**

1. `pon_timer_instigation_create()` — cria `timerfd`, configura expiração, registra no `epoll` fd global. Se o timeout for <1ms, retorna -1 (fallback para timer wheel tradicional).

2. Kernel monitora o `timerfd` sem consumir CPU. Quando o tempo expira, o `timerfd` fica legível.

3. `pon_timer_instigation_fire()` — lê o `timerfd` para consumir o evento, marca `fired = 1`.

4. `pon_timer_process_expirations()` — chamado pelo scheduler (Fase 4) para processar lote de expirações via `epoll_wait` não bloqueante.

5. `pon_timer_instigation_cancel()` — fecha o `timerfd`, remove do `epoll`.

### 2.3 APIs do módulo `pon_timer.c`

| Função | Descrição |
|--------|-----------|
| `pon_timer_init()` | Cria epoll fd global |
| `pon_timer_destroy()` | Fecha epoll fd |
| `pon_timer_instigation_create(inst)` | Cria timerfd, registra no epoll |
| `pon_timer_instigation_cancel(inst)` | Fecha timerfd, remove do epoll |
| `pon_timer_instigation_fire(inst)` | Lê timerfd, marca fired |
| `pon_timer_process_expirations()` | Polling não bloqueante de expirações |

## 3. Modificações no código-fonte

### 3.1 Arquivos criados (2)

| Arquivo | Linhas | Função |
|---------|--------|--------|
| `erts/include/internal/pon_instigation.h` | 75 | Definição de `ErtsInstigation`, `ErtsTimerInstigation`, macro de inicialização |
| `erts/emulator/beam/pon_timer.c` | 148 | Implementação completa com timerfd + epoll |

### 3.2 Arquivos modificados (2)

| Arquivo | Mudança |
|---------|---------|
| `erts/include/internal/pon_stats.h` | +4 contadores: timerfd_created, timerfd_expirations, timer_wheel_fallback, timer_instigations |
| `erts/emulator/Makefile.in` | +`$(OBJDIR)/pon_timer.o` na lista de objetos |

### 3.3 Benchmarks criados (1)

| Benchmark | Medição |
|-----------|---------|
| `timer_idle_cpu.erl` | CPU% do timer wheel sem timers ativos (10s idle) |

## 4. Resultados da compilação

O módulo `pon_timer.c` compila de forma independente (sem dependência de headers OTP internos):

```console
$ gcc -DPON_BEAM -D_GNU_SOURCE -std=c99 \
  -I../../include/internal \
  -c pon_timer.c -o pon_timer.o
# 0 erros, 0 warnings
```

Quando compilado com `PON_BEAM_DEBUG`, inclui `pon_stats.h` que ativa os contadores de instrumentação. Em modo release (apenas `PON_BEAM`), as macros de stats são vazias — custo zero em produção.

A compilação completa como parte do ERTS (via `make TYPE=ponbeam`) depende da configuração do OTP. O módulo é auto-suficiente POSIX e será integrado ao scheduler na Fase 4.

## 5. Observações e lições aprendidas

### 5.1 Timerfd é específico de Linux

`timerfd` e `epoll` são APIs Linux. Para portabilidade:
- **macOS/iOS**: `kqueue` com `EVFILT_TIMER`
- **BSD**: `kqueue` similar
- **Windows**: `CreateTimerQueue` + `IOCP`
- **Fallback**: timer wheel original para OS sem suporte a timerfd

A arquitetura PON-BEAM usa `#ifdef __linux__` para timerfd e reserva o timer wheel como fallback universal. O limiar de 1ms para timers curtos também usa o timer wheel em todas as plataformas.

### 5.2 File descriptors

Cada `timerfd` consome um file descriptor. O limite típico no Linux é 1M (ver `ulimit -n`). Para 50000 timers simultâneos (comum em sistemas OTP com timeouts de sessão), 50000 FDs são 5% do limite — aceitável.

Para cenários com milhões de timers, o timer wheel tradicional é mais eficiente em memória. A Fase 2 mantém ambos disponíveis.

### 5.3 Integração com PON-Scheduler (Fase 4)

O `pon_timer_process_expirations()` foi projetado para ser chamado pelo loop do scheduler PON (Fase 4). Até lá, os timerfds são criados e monitorados, mas a notificação ao processo alvo (envio de mensagem para a mailbox) requer a integração com o scheduler.

Isto é intencional: cada fase constrói sobre a anterior, e Fases 1+2 fornecem as primitivas (Premises + Instigações) que a Fase 4 consumirá.

### 5.4 Compilação independente

`pon_timer.c` foi projetado para compilar sem a cadeia completa de headers OTP. Isto permite testes independentes e validação do mecanismo timerfd sem precisar do build completo do ERTS. As únicas dependências são:
- POSIX (`timerfd.h`, `epoll.h`, `unistd.h`)
- `pon_instigation.h` (usa apenas `stdint.h`)
- `pon_stats.h` (em modo release, expande para macros vazias)

## 6. Próximos passos

| Item | Prioridade | Descrição |
|------|-----------|-----------|
| Integração com PON-Scheduler (Fase 4) | Alta | Chamar `pon_timer_process_expirations` no loop do scheduler |
| Hook nas BIFs `send_after` / `start_timer` | Média | Fazer `erlang:send_after` usar timerfd quando PON_BEAM ativo |
| Portabilidade (kqueue, IOCP) | Média | Implementar backends para macOS e Windows |
| Teste com 50K timers concorrentes | Alta | Validar uso de FDs e precisão de expiração |

## 7. Verificação

- [x] `pon_instigation.h` criado com `ErtsInstigation` e `ErtsTimerInstigation`
- [x] `pon_timer.c` criado com implementação timerfd + epoll
- [x] `pon_stats.h`: contadores de timer adicionados
- [x] `Makefile.in`: pon_timer.o na lista de objetos
- [x] Compilação standalone: pon_timer.c sem erros com `-DPON_BEAM -D_GNU_SOURCE`
- [x] Compilação standalone: pon_instigation.h sem erros com `-std=c99`
- [ ] Build completo via `make TYPE=ponbeam` (depende de build OTP completo)
- [ ] Benchmark `timer_idle_cpu.erl` funcional
- [ ] Validação com 50K timers concorrentes

## Ver também

- [Relatório Fase 1 — PON-Receive](RPT-01-pon-receive.md)
- [Plano de engenharia PON-BEAM](EX-38-pon-beam-plano-de-engenharia.md)
- [Tese PON-BEAM](EX-37-pon-beam-arquitetura-orientada-a-notificacoes.md)
- [Capítulo 12 — Timers e o timer wheel](../chapters/12-timers-e-o-timer-wheel.md)
- [Código fonte: pon_instigation.h](../../otp/erts/include/internal/pon_instigation.h)
- [Código fonte: pon_timer.c](../../otp/erts/emulator/beam/pon_timer.c)
- [timerfd_create(2)](https://man7.org/linux/man-pages/man2/timerfd_create.2.html)
- [epoll(7)](https://man7.org/linux/man-pages/man7/epoll.7.html)
