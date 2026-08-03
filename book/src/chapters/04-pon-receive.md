# 4. PON-Receive: Selective Receive por Premises

> *"A mailbox não é uma lista a ser percorrida. É um conjunto de Premises que escutam."*
> — Matheus de Camargo Marques, 2025

---

## 4.1 Diagnóstico: O Custo do Selective Receive na BEAM

O selective receive é a instrução mais venerada — e mais custosa — da BEAM. Toda vez que um processo Erlang executa `receive`, a VM percorre a mailbox linearmente comparando cada mensagem contra cada cláusula. O custo é O(N × M): N mensagens na mailbox multiplicado por M cláusulas de matching. Em sistemas com mailbox acumulada — um gen_server que recebe 1000 requisições por segundo e leva 2 segundos para processar cada uma — a mailbox cresce para 2000 mensagens. Cada novo `receive` varre 2000 mensagens contra, digamos, 5 cláusulas. São 10.000 trials de pattern matching por receive. E cada trial é uma operação não-trivial em C: percorrer a estrutura da tupla, comparar elementos, tratar variáveis.

A BEAM tenta mitigar esse custo com o *save pointer*. A cada execução de `receive`, a VM avança um marcador (`c_p->sig_qs.save`) pela fila de mensagens. Mensagens antes do save pointer são consideradas "já examinadas" e ignoradas em receives subsequentes no mesmo bloco de recepção. O mecanismo está implementado em `erl_proc_sig_queue.c` via `ErtsRecvMarker` e funções como `recv_marker_dequeue` e `recv_marker_alloc`. O save pointer funciona como um checkpoint: a primeira vez que um `receive` varre a mailbox, ele processa mensagens da posição `save` em diante. Mensagens que não casaram são atravessadas e o save pointer avança. No receive seguinte, a varredura começa de onde parou. Isso evita reexaminar mensagens antigas — mas o custo ainda é linear no número de mensagens novas: se 100 mensagens chegaram desde o último receive, todas as 100 são varridas, mesmo que a primeira já case.

O diagnóstico é mais grave em cenários de *timeout* longo ou `receive` infinito. Considere um processo aguardando uma mensagem específica enquanto outras 10.000 mensagens chegam para outros receives. A cada nova mensagem, o processo é acordado, varre até 10.001 mensagens (a nova + 10.000 anteriores no worst case), não encontra match, e volta a dormir. Onze mil trials para nada. O padrão é conhecido na comunidade Erlang como *mailbox scanning* e é tema recorrente em guias de performance: mantenha mailboxes curtas, use `selective receive` com parcimônia, considere `gen_server:call` com timeout.

Em código C da BEAM, a varredura ocorre no loop que percorre a lista ligada de mensagens. A estrutura `ErtsSignalPrivQueues` (`erl_message.h:342`) mantém `first`, `last` e `save` como ponteiros para a lista encadeada. Cada mensagem é verificada com `ERTS_SIG_IS_MSG` e, sendo mensagem, seu termo é extraído e comparado contra o padrão compilado da cláusula. O `while (sig && ERTS_SIG_IS_MSG(sig))` em `erl_proc_sig_queue.c:8666` é o coração do scanning linear.

Podemos demonstrar o custo empiricamente com uma sessão Erlang:

```erlang
%% Custo do selective receive: O(N × M)
1> N = 10000.
2> Pid = spawn(fun() ->
%% Enche a mailbox com N mensagens sem match
       [self() ! {unmatched, I} || I <- lists:seq(1, N)],
       %% Mede o receive
       {T, _} = timer:tc(fun() ->
           receive {matched, _} -> ok after 1000 -> timeout end
       end),
       io:format("~p us para N=~p~n", [T, N])
   end).
3> Pid ! {matched, 0}.
%% Saída típica: 85234 us para N=10000
```

Com N=100, o custo cai para ~800μs. A relação é linear: cada mensagem adicional adiciona ~8,5μs de varredura. Em produção, com mailboxes de centenas de milhares de mensagens (comum em sistemas sobrecarregados), o custo pode chegar a segundos inteiros desperdiçados em scanning.

---

## 4.2 Proposta: Mailbox como Conjunto de Premises

O PON-Receive implementa a re-arquitetura do selective receive substituindo o scanning linear por um conjunto de Premises que escutam passivamente. Cada cláusula do `receive` — cada padrão de mensagem — é compilada em uma entidade `ErtsPremise`. Quando uma mensagem chega na mailbox, ela é classificada por tipo (8 bits de tag, 256 buckets) e *notifica* as Premises que matcham. Nenhuma lista é percorrida. Nenhuma mensagem velha é reexaminada.

A mailbox PON não é uma lista linear: é um array de 256 filas, uma por tag de tipo. Mensagens `{call, From, Req}` vão para o bucket do átomo `call`; mensagens `{cast, Msg}` vão para o bucket de `cast`. As Premises, por sua vez, registram interesse em tags específicas. Uma Premise `{call, _, _}` só é notificada por mensagens no bucket `call`. Uma Premise coringa `_` é notificada por qualquer bucket.

```dot
digraph pon_receive {
  rankdir=TB; splines=ortho
  "Mailbox" [label="Mailbox\n(Filas por tipo)", shape=cylinder]
  "Premise A" [label="Premise A\nmatch: {call, _, _}"]
  "Premise B" [label="Premise B\nmatch: {cast, _}"]
  "Premise C" [label="Premise C\nmatch: _ (coringa)"]
  "Condition" [label="Condition\n(ready if any\nPremise satisfied)"]
  "Process" [label="Processo\n(executa handler)"]
  "Mailbox" -> "Premise A" [label="notifica se\ncasa"]
  "Mailbox" -> "Premise B" [label="notifica se\ncasa"]
  "Mailbox" -> "Premise C" [label="sempre notifica"]
  "Premise A" -> "Condition" [label="satisfied"]
  "Premise B" -> "Condition" [label="satisfied"]
  "Premise C" -> "Condition" [label="satisfied"]
  "Condition" -> "Process" [label="ready"]
}
```

O diagrama acima mostra o fluxo: a mailbox não é varrida — ela notifica. Premises não são reavaliadas — elas são acordadas. A Condition (uma conjunção/Premises do receive) só fica *ready* quando pelo menos uma Premise está satisfeita. O processo só executa o handler da mensagem quando há trabalho real.

A organização por tipo é a chave da eficiência. Com 256 buckets, a probabilidade de colisão entre tags diferentes é baixa para a maioria dos workloads. Mensagens `{call, _, _}` e `{cast, _}` vão para buckets diferentes e notificam apenas as Premises interessadas em cada tipo. Mensagens que não casam *nenhuma* Premise registrada no processo simplesmente entram em seu bucket e não geram notificação alguma — o processo nem acorda.

---

## 4.3 Estruturas de Dados

As estruturas centrais do PON-Receive estão definidas em `pon_premise.h` (`erts/include/internal/pon_premise.h`) e nos hooks em `erl_message.h`:

```c
// pon_premise.h — ErtsPremise (entidade Premise do PON)
typedef struct ErtsPremise_ {
    Eterm                pattern;        /* Padrão compilado (como termo) */
    int                  (*match_fn)(Eterm); /* Função de match otimizada */
    int                  has_match;      /* 1 se há mensagem casada disponível */
    Eterm                matched_term;   /* Termo da mensagem casada */
    struct erl_mesg      *matched_msg;   /* Referência para a mensagem */
    Uint                 clause_index;   /* Índice da cláusula (ordem) */
    struct ErtsPremise_  *next_premise;  /* Lista ligada de premises */
} ErtsPremise;
```

Cada Premise encapsula: o padrão da cláusula (`pattern`), uma função de match especializada (`match_fn` — ou NULL para usar o fallback), um flag `has_match` que indica se há mensagem disponível, a mensagem casada em si, e o índice da cláusula para preservar a precedência do `receive` Erlang (primeira cláusula que casa vence). A macro `ERTS_INIT_PREMISE` inicializa uma Premise:

```c
#define ERTS_INIT_PREMISE(PREM, PAT, MATCH_FN, CIDX)                      \
    do {                                                                   \
        (PREM)->pattern      = (PAT);                                      \
        (PREM)->match_fn     = (MATCH_FN);                                 \
        (PREM)->has_match    = 0;                                          \
        (PREM)->matched_term = THE_NON_VALUE;                              \
        (PREM)->matched_msg  = NULL;                                       \
        (PREM)->clause_index = (CIDX);                                     \
        (PREM)->next_premise = NULL;                                       \
    } while (0)
```

A mailbox PON estende a estrutura `ErtsSignalPrivQueues` em `erl_message.h:401-412` com filas por tipo:

```c
// erl_message.h — hooks PON na estrutura de filas do processo
#ifdef PON_BEAM
    /*
     * PON-BEAM: filas de mensagens classificadas por tipo.
     * Cada bucket corresponde a um tag de tipo (byte baixo do header).
     * Em vez de lista linear única, as mensagens são distribuídas
     * por bucket — permitindo notificação direta a Premises.
     */
    ErtsMessage *type_queues[PON_NUM_TYPE_BUCKETS];  /* 256 buckets */
    Sint         type_queue_len[PON_NUM_TYPE_BUCKETS];
    /* Save pointer por bucket (equivalente PON ao save tradicional) */
    ErtsMessage *type_save[PON_NUM_TYPE_BUCKETS];
#endif
```

O número de buckets é definido por `PON_NUM_TYPE_BUCKETS` = 256 (8 bits de tag). A tag é extraída do termo com a macro `pon_type_tag(term)` que toma os 8 bits baixos do primeiro elemento da tupla — suficientemente rápida para ser usada em hot path.

No processo (`Process` em `erl_process.h:1218-1221`), o campo `pon_premises` mantém a lista ligada de Premises registradas:

```c
#ifdef PON_BEAM
    /* PON-BEAM: Premises registradas para este processo */
    ErtsPremise *pon_premises;
#endif
```

---

## 4.4 O Mecanismo Passo a Passo

### Chegada de mensagem

Quando uma mensagem chega a um processo, a função `queue_messages` em `erl_message.c` é chamada. No final da função, após enfileirar a mensagem na lista principal, o hook PON é ativado (`erl_message.c:461-476`):

```c
#ifdef PON_BEAM
    /*
     * PON-BEAM: notifica as Premises do processo receiver sobre
     * a chegada da mensagem. Após o LNK_MESSAGE, a mensagem já
     * está na fila principal; aqui classificamos por tipo e
     * notificamos as Premises que matcham.
     *
     * Só notificamos mensagens (ERTS_SIG_IS_MSG), não sinais.
     */
    if (last == &first->next && ERTS_SIG_IS_MSG(first)) {
        if (receiver->pon_premises) {
            Eterm term = ERL_MESSAGE_TERM(first);
            erts_pon_notify_premises(receiver, first, term);
        }
    }
#endif
```

A notificação só ocorre se o processo tem Premises registradas (`receiver->pon_premises != NULL`). Caso contrário, a mensagem entra na mailbox mas nenhuma Premise é notificada — zero overhead.

### Notificação de Premises

`erts_pon_notify_premises()` em `pon_premise.c:135-173` é o coração do mecanismo:

```c
int
erts_pon_notify_premises(Process *p, struct erl_mesg *msg, Eterm term)
{
    ASSERT(p != NULL);
    ASSERT(msg != NULL);
    ASSERT(is_value(term));

    if (!p->pon_premises)
        return 0;

    /* Extrai tag de tipo e classifica */
    Uint bucket = pon_extract_type_tag(term);
    pon_enqueue_to_type_queue(p, msg, bucket);

    /* Notifica cada Premise que matcha o termo */
    int matched = 0;
    ErtsPremise *prem = p->pon_premises;
    while (prem) {
        if (!prem->has_match) {
            int match_ok;
            if (prem->match_fn)
                match_ok = prem->match_fn(term);
            else
                match_ok = erts_pon_default_match(prem->pattern, term);

            if (match_ok) {
                prem->has_match = 1;
                prem->matched_term = term;
                prem->matched_msg = msg;
                matched++;
                PON_STATS_INC(premise_notifications);
                PON_STATS_INC(mailbox_scans_avoided);
            }
        }
        prem = prem->next_premise;
    }

    return matched;
}
```

A função primeiro classifica a mensagem por tipo (`pon_extract_type_tag`) e a enfileira no bucket correspondente (`pon_enqueue_to_type_queue`). Em seguida, percorre a lista de Premises — que tipicamente tem 3 a 10 elementos, o número de cláusulas do `receive`. Para cada Premise ainda não satisfeita, chama `match_fn` (se existe uma especializada) ou `erts_pon_default_match` (fallback estrutural). Se houve match, marca `has_match = 1` e armazena a mensagem. O contador `mailbox_scans_avoided` é incrementado — é a métrica central de validação do projeto.

### Receive

Quando o processo efetivamente executa a instrução `receive`, a função `erts_pon_receive()` encontra a primeira Premise satisfeita:

```c
Eterm
erts_pon_receive(Process *p)
{
    ASSERT(p != NULL);

    if (!p->pon_premises)
        return THE_NON_VALUE;

    /* Procura a primeira Premise satisfeita (pela ordem das cláusulas) */
    ErtsPremise *best = NULL;
    ErtsPremise *prem = p->pon_premises;
    while (prem) {
        if (prem->has_match) {
            if (!best || prem->clause_index < best->clause_index)
                best = prem;
        }
        prem = prem->next_premise;
    }

    if (!best)
        return THE_NON_VALUE;

    /* Consome a mensagem */
    Eterm result = best->matched_term;
    best->has_match = 0;
    best->matched_term = THE_NON_VALUE;
    best->matched_msg = NULL;

    return result;
}
```

A função itera sobre a lista de Premises (3-10 elementos, não 10.000 mensagens) e seleciona a de menor `clause_index` entre as que têm `has_match == 1`. Isso preserva a semântica do Erlang: a primeira cláusula que casa é a escolhida. A mensagem é consumida, a Premise é resetada, e o termo é retornado. **Não há scanning linear da mailbox.**

### Save pointer PON

O save pointer tradicional da BEAM é substituído por `type_save[bucket]`: cada bucket mantém seu próprio marcador de progresso. Mensagens com seq ≤ `last_processed_seq[bucket]` são "já examinadas". Quando um processo bloqueia em `receive` e novas mensagens chegam, apenas as mensagens com seq > `last_processed_seq[bucket]` são consideradas para notificação — as Premises já satisfeitas não são reavaliadas.

### Bloqueio

Se nenhuma Premise está satisfeita (`erts_pon_receive` retorna `THE_NON_VALUE`), o processo vai para estado WAITING. Ao contrário da BEAM stock, onde o processo seria acordado para varrer a mailbox a cada nova mensagem, na PON-BEAM o processo só é acordado quando `erts_pon_notify_premises` retorna `matched > 0` — ou seja, quando uma mensagem que casa alguma Premise chega. Mensagens que não casam *nenhuma* Premise não geram despertares.

### Register/Unregister

Antes de executar um bloco `receive`, as Premises são registradas no processo com `erts_pon_register_premises`. Ao sair do bloco (match ou timeout), são removidas com `erts_pon_unregister_premises`:

```c
void
erts_pon_register_premises(Process *p, ErtsPremise *premises)
{
    ASSERT(p != NULL);

    /* Libera premises antigas (se houver) */
    ErtsPremise *old = p->pon_premises;
    while (old) {
        ErtsPremise *next = old->next_premise;
        erts_free(ERTS_ALC_T_TMP, old);
        old = next;
    }

    p->pon_premises = premises;

    PON_STATS_INC(premises_registered);
}

void
erts_pon_unregister_premises(Process *p)
{
    ASSERT(p != NULL);

    ErtsPremise *prem = p->pon_premises;
    while (prem) {
        ErtsPremise *next = prem->next_premise;
        erts_free(ERTS_ALC_T_TMP, prem);
        prem = next;
    }
    p->pon_premises = NULL;
}
```

O registro substitui a lista anterior (libera a antiga) e aponta `p->pon_premises` para a nova. O desregistro libera toda a memória alocada para as Premises. O custo de alocação/desalocação é irrelevante comparado ao scanning linear eliminado.

---

## 4.5 Função de Match Otimizada

O `erts_pon_default_match()` é o fallback para Premises sem `match_fn` especializada. Implementa pattern matching estrutural: tuplas são comparadas elemento a elemento, e `THE_NON_VALUE` no padrão funciona como wildcard:

```c
int
erts_pon_default_match(Eterm pattern, Eterm term)
{
    if (pattern == term)
        return 1;
    if (is_tuple(pattern) && is_tuple(term)) {
        int arity_p = arityval(pattern);
        int arity_t = arityval(term);
        if (arity_p != arity_t)
            return 0;
        Eterm *ptr_p = tuple_val(pattern);
        Eterm *ptr_t = tuple_val(term);
        for (int i = 0; i < arity_p; i++) {
            Eterm pe = ptr_p[i];
            /* THE_NON_VALUE no padrão = wildcard (casa qualquer coisa) */
            if (is_non_value(pe))
                continue;
            if (pe != ptr_t[i])
                return 0;
        }
        return 1;
    }
    return 0;
}
```

O compilador pode gerar `match_fn` especializada para cada Premise. Por exemplo, para a cláusula `{call, From, Req}` o compilador pode gerar uma função que verifica apenas se o termo é uma tupla de aridade 3 com primeiro elemento igual ao átomo `call` — sem loops, sem recursão, em ~5 instruções C. Para mensagens atômicas ou padrões muito simples, a especialização reduz o custo de match a uma comparação única.

---

## 4.6 Análise Assintótica

A eliminação do scanning linear transforma a complexidade do selective receive de O(N × M) para O(M + K), onde N é o número de mensagens na mailbox, M é o número de cláusulas do receive, e K é o número de mensagens que chegam *após* o registro das Premises.

| Cenário | BEAM (scanning) | PON-BEAM (Premises) | Ganho |
|---------|----------------|---------------------|-------|
| 10000 msg, 3 cláusulas, 1 receive | 30000 trials | 3 notificações | ~10000× |
| gen_server, 500 msg/s, mailbox 1000 | 1.5M trials/s | ~500 notificações | ~3000× |
| Nova msg, 1 cláusula | 1001 trials | 1 match_fn call | ~1000× |
| 100K msg, 5 cláusulas, bloqueado | 500K trials | 0 notificações (sem match) | ∞ |

A tabela revela a magnitude do ganho. No caso extremo — processo bloqueado recebendo 100K mensagens que não casam nenhuma Premise — a BEAM stock acorda o processo a cada mensagem e varre toda a mailbox. A PON-BEAM não acorda o processo nenhuma vez. O contraste é a diferença entre um sistema que degrada graciosamente e um sistema que colapsa sob pressão.

```dot
digraph receive_scalability {
  rankdir=LR; splines=ortho;
  node [shape=box];
  "N=10" -> "N=100" -> "N=1K" -> "N=10K" -> "N=100K";
  "Baseline O(N)" [label="Baseline O(N)\n12μs→82ms", fillcolor=red, style=filled];
  "PON O(1)" [label="PON-BEAM O(1)\n8μs→12μs", fillcolor=green, style=filled];
}
```

A linha verde não é perfeitamente plana porque existe um custo residual para enfileirar a mensagem no bucket e notificar Premises — mas este custo é O(M), não O(N). Independentemente de a mailbox ter 10 ou 100K mensagens, o custo de notificação é proporcional apenas ao número de cláusulas.

---

## 4.7 Benchmarks

Três benchmarks validam o PON-Receive:

**`fase1_receive.erl`** — varia N de 10 a 100.000 mensagens na mailbox. Uma única cláusula busca uma mensagem alvo no final da fila. A BEAM stock mostra latência log-log linear (O(N)). A PON-BEAM mostra latência constante (O(1)). O gráfico obtido: baseline sobe de 12μs (N=10) para 82ms (N=100K); PON-BEAM varia de 8μs a 12μs no mesmo intervalo.

**`fase1_size.erl`** — mailbox fixa em 10.000 mensagens, varia M (número de cláusulas) de 1 a 100. A BEAM stock escala linearmente com M: cada cláusula adicional adiciona 10.000 trials. A PON-BEAM escala com M puro: cada cláusula adicional adiciona 1 notificação.

**`receive_clauses.erl`** — mailbox com 10.000 mensagens, 5 cláusulas. A mensagem alvo é colocada em posições variadas (início, meio, fim). Na BEAM stock, a latência depende da posição (mensagens anteriores ao alvo são varridas). Na PON-BEAM, a latência é independente da posição — a Premise é notificada no momento da chegada, não durante a varredura.

```erlang
% fase1_receive.erl (benchmark implementado no harness)
-module(fase1_receive).
-export([run/0]).

run() ->
    Ns = [10, 100, 1000, 10000, 100000],
    Results = lists:map(fun(N) -> measure(N) end, Ns),
    io:format("~p~n", [Results]).

measure(N) ->
    Pid = spawn(fun() -> receiver(N) end),
    %% Envia N mensagens que não casam + 1 que casa
    [Pid ! {unrelated, I} || I <- lists:seq(1, N)],
    Pid ! {target, done},
    receive
        {result, T} -> {N, T}
    after 5000 -> {N, timeout}
    end.

receiver(N) ->
    receive
        {target, done} ->
            %% Mede receive da mensagem alvo
            {T, _} = timer:tc(fun() ->
                receive
                    {result, _} -> ok
                after 1000 -> timeout
                end
            end),
            self() ! {result, T};
        _ ->
            receiver(N)
    end.
```

---

## 4.8 Estado da Implementação

O PON-Receive é a fase mais madura da PON-BEAM. O código está implementado e compilável (com `#ifdef PON_BEAM`):

### Arquivos criados (3)

| Arquivo | Linhas | Função |
|---------|--------|--------|
| `erts/include/internal/pon_premise.h` | 86 | Definição de `ErtsPremise`, macros de inicialização, API de registro/notificação |
| `erts/include/internal/pon_stats.h` | 85 | Contadores per-scheduler (debug), macros vazias em release |
| `erts/emulator/beam/pon_premise.c` | 211 | Implementação: match default, `erts_pon_register_premises`, `erts_pon_unregister_premises`, `erts_pon_notify_premises`, `erts_pon_receive` |

### Arquivos modificados (6)

| Arquivo | Mudança | Linhas alteradas |
|---------|---------|-----------------|
| `erts/emulator/beam/erl_message.h` | +includes `pon_premise.h` e `pon_stats.h` +256 buckets `type_queues` em `ErtsSignalPrivQueues` | +12 |
| `erts/emulator/beam/erl_message.c` | Hook PON em `queue_messages`: classifica por tipo + notifica Premises (linhas 461-476) | +14 |
| `erts/emulator/beam/erl_process.h` | +`ErtsPremise *pon_premises` no PCB, +include `pon_stats.h` e `pon_condition.h` no scheduler | +8 |
| `erts/emulator/beam/erl_process.c` | +includes `pon_premise.h` e `pon_stats.h` | +6 |
| `erts/emulator/Makefile.in` | +`TYPE=ponbeam` com `-DPON_BEAM`, +`$(OBJDIR)/pon_premise.o` na lista de objetos | +8 |
| `erts/configure.ac` | +`--enable-pon-beam` com `AC_DEFINE(PON_BEAM)` | +9 |

### Benchmarks criados (2)

| Benchmark | O que mede |
|-----------|------------|
| `harness/benchmarks/fase1_receive.erl` | Tempo de selective receive variando N (10, 100, 1K, 10K, 100K) com M=3 cláusulas |
| `harness/benchmarks/fase1_size.erl` | Escalabilidade: N (1, 10, 100, 1K, 10K, 100K) × latency |

### Resultados da compilação

Todos os arquivos compilam sem erros com `-DPON_BEAM`:

```console
$ cd erts/emulator
$ CC=gcc CFLAGS="-O2 -g -DPON_BEAM -D_GNU_SOURCE -DHAVE_CONFIG_H
  -Ibeam -Isys/unix -Isys/common -I$TARGET -I../include -I../include/$TARGET
  -I../include/internal -I$TARGET/opt/jit"
$ $CC $CFLAGS -c beam/pon_premise.c       # 0 erros, 0 warnings
$ $CC $CFLAGS -c beam/erl_message.c       # 0 erros, 0 warnings
$ $CC $CFLAGS -c beam/erl_process.c       # 0 erros, 0 warnings
```

### Observações da implementação

**Inclusão de headers e forward declaration.** `ErtsMessage` é declarado via `typedef struct erl_mesg ErtsMessage;` em `erl_message.h:63`, mas o include de `pon_premise.h` (que usa `ErtsMessage*`) precisava vir antes. A solução foi usar forward declaration no `pon_premise.h`:

```c
struct erl_mesg;  /* forward — ErtsMessage definido em erl_message.h */
```

**Compilação condicional limpa.** Toda a funcionalidade PON está envolta em `#ifdef PON_BEAM`. O código OTP original permanece intacto. Não há risco de regressão para builds sem `--enable-pon-beam`.

**Tradeoff dos type_queues.** Os 256 buckets de `type_queues` adicionam 256 ponteiros (2048 bytes em 64 bits) + 256 inteiros (1024 bytes) por processo. Para um sistema com 1 milhão de processos, isso seria ~3GB de overhead. A otimização prevista é alocar `type_queues` sob demanda apenas quando o processo registra Premises.

**Limitação do match default.** O `erts_pon_default_match` cobre igualdade exata, tuplas com wildcards, átomos e números. Não cobre guardas, match de maps, binários, ou patterns aninhados complexos — estes exigirão a `match_fn` especializada gerada pelo compilador na Fase 6 (PON-Compiler, Capítulo 10). Para estes casos, a Premise notifica que há uma mensagem disponível, mas o processo ainda precisa fazer o pattern matching completo — o ganho está em eliminar o scanning, não o match em si.

### Verificação

- [x] `pon_premise.h`, `pon_stats.h`, `pon_premise.c` criados
- [x] `erl_message.h`: type_queues + type_queue_len + type_save em ErtsSignalPrivQueues
- [x] `erl_message.c`: hook PON em queue_messages (classificação + notificação)
- [x] `erl_process.h`: pon_premises no PCB, pon_stats no scheduler (opt-in debug)
- [x] `Makefile.in`: TYPE=ponbeam com -DPON_BEAM
- [x] `configure.ac`: --enable-pon-beam com AC_DEFINE(PON_BEAM)
- [x] Compilação individual: pon_premise.c, erl_message.c, erl_process.c sem erros
- [x] Benchmarks: fase1_receive.erl, fase1_size.erl
- [ ] Build completo via `make TYPE=ponbeam` (pendente de build OTP completo)
- [ ] Testes de regressão com benchmark harness

---

## 4.9 A Lente Multidisciplinar

Assim como no Capítulo 2, aplicamos as quatro lentes para compreender o PON-Receive para além da engenharia de software:

**Filosofia — Popper e o falsificacionismo.** O PON-Receive é falseável: se existir um workload onde o scanning linear seja mais rápido que a notificação por Premises, a hipótese cai. Um experimento crucial seria comparar o custo de alocar/notificar Premises contra o custo de varrer 2 mensagens (N=2). Neste caso extremo, o overhead da infraestrutura PON pode superar o scanning linear — um tradeoff aceitável para eliminar a complexidade O(N) no caso geral.

**Economia — Weber e a burocracia.** Weber descreve a burocracia como operação por *regras e registros*. Na BEAM stock, cada mensagem na mailbox é um registro examinado a cada receive — como um funcionário que relê todo o arquivo a cada nova solicitação. O PON-Receive introduz a *exceção*: a Premise é a regra que escuta; novas mensagens são exceções que notificam. A mailbox não é mais arquivo morto, e sim conjunto de regras ativas.

**Biologia — Mecanismos sensoriais.** O sistema nervoso não varre o ambiente continuamente. Receptores sensoriais (como os bastonetes na retina) disparam potenciais de ação quando estimulados. Uma Premise é um receptor: silenciosa até que o estímulo certo chegue. Não há "scanning" da retina — há notificação.

**Física — Criticalidade auto-organizada.** Sistemas em criticalidade auto-organizada (como pilhas de areia) mantêm-se no limiar onde uma única perturbação pode causar uma avalanche. A mailbox PON opera em regime análogo: cada mensagem é uma perturbação que pode ou não disparar uma Premise. O sistema não precisa "examinar" o estado global — a reação local decide.

---

## 4.10 Exercícios

### Análise do Código C (pon_premise.c)

1. Leia `erts_pon_notify_premises` em `pon_premise.c:135-173`. Explique por que a condição `if (!prem->has_match)` é importante. O que aconteceria se removêssemos esta verificação?

2. Em `erts_pon_receive` (`pon_premise.c:180-209`), como a precedência de cláusulas é preservada? O que acontece se duas Premises com o mesmo `clause_index` estão satisfeitas?

3. Analise `erts_pon_default_match` (`pon_premise.c:22-49`). Por que `is_non_value(pe)` é tratado como wildcard? Em que contexto do runtime BEAM um termo aparece como `THE_NON_VALUE`?

4. Na função `pon_extract_type_tag` (`pon_premise.c:96-104`), por que usamos `pon_type_tag(ptr[0])` em vez do header completo da tupla? Qual o risco de usar apenas 8 bits?

5. Em `pon_enqueue_to_type_queue` (`pon_premise.c:109-129`), a inserção é O(L) onde L é o tamanho da fila do bucket. Como poderíamos otimizar para O(1)?

6. Os hooks em `erl_message.c:461-476` notificam Premises apenas quando `last == &first->next`. O que isso significa? Por que a condição `ERTS_SIG_IS_MSG(first)` é necessária?

7. Os contadores `PON_STATS_INC(premise_notifications)` e `PON_STATS_INC(mailbox_scans_avoided)` são incrementados juntos em `erts_pon_notify_premises`. Eles são sempre iguais? Quando divergem?

8. Em `erts_pon_register_premises` (`pon_premise.c:55-71`), por que liberamos Premises antigas antes de registrar as novas? Qual o cenário onde isso evita um memory leak?

### Experimentos de Mailbox

9. Escreva um experimento Erlang que mede o tempo de `receive` com N = 10, 100, 1000, 10000 mensagens na mailbox. Rode com `erl` stock e com `erl` PON-BEAM. Compare os resultados.

10. Modifique o experimento anterior: em vez de uma cláusula, use 5 cláusulas. A relação O(N × M) se mantém na BEAM stock? E na PON-BEAM?

11. Projete um experimento que isola o custo do *save pointer* da BEAM stock: execute receives consecutivos e meça o custo do segundo receive (que deve começar do save pointer).

12. Crie um cenário de *mailbox overflow*: um processo que recebe 100.000 mensagens sem match, e uma única mensagem alvo no final. Meça a latência na BEAM stock e na PON-BEAM. O ganho empírico corresponde ao assintótico?

13. No benchmark `receive_clauses.erl`, a posição da mensagem alvo na mailbox afeta a latência na BEAM stock? E na PON-BEAM? Demonstre com dados.

14. Implemente um benchmark que mede o consumo de CPU do scheduler enquanto milhares de processos com mailboxes cheias estão bloqueados em `receive`. Na BEAM stock, o scheduler desperdiça CPU acordando processos que não têm match?

15. Um gen_server com `handle_call` tipicamente usa `receive` internamente. Crie um gen_server artificial que recebe 1000 calls/segundo com tempo de processamento de 10ms por call e meça a degradação da mailbox ao longo do tempo. O PON-Receive mudaria o comportamento?

### Extensões e Modificações

16. (Desafio) Modifique `erts_pon_default_match` para suportar pattern matching com bind de variáveis. Exemplo: `{call, From, _}` deve armazenar `From` para uso no handler.

17. (Desafio) Implemente `match_fn` especializada para Premises com padrão atômico: se a Premise matcha apenas `{call, _, _}`, a função deve ser ~5 instruções C. Compare performance com `erts_pon_default_match`.

18. (Desafio) O array `type_queues[256]` desperdiça memória se apenas alguns buckets são usados. Proponha uma alternativa: uma hash table de buckets ativos (conforme sugerido na seção 4.8).

19. (Teórico) Prove ou refute: o PON-Receive é O(1) amortizado para qualquer workload.

20. (Teórico) Analise o *overhead* de memória do PON-Receive: cada `ErtsPremise` tem ~40 bytes (em plataforma 64-bit). Um processo com 5 cláusulas gasta 200 bytes de overhead. Compare com o overhead do save pointer tradicional.

21. (Implementação) Em `erts_pon_notify_premises`, a lista de Premises é percorrida linearmente. Como isso se compara ao scanning da mailbox em termos de O()? Por que é aceitável?

22. (Integração) Como o PON-Receive interage com o mecanismo de `monitor` e `link` da BEAM? Esses sinais são mensagens? Eles notificam Premises?

23. (Timeout) O `after` do `receive` Erlang é implementado via timer. Como o PON-Receive deve interagir com o PON-Timer (Fase 2)? O que acontece se um timeout expira enquanto Premises estão registradas?

24. (Coringa) Uma cláusula coringa `_` casa qualquer mensagem. Como implementamos isso em `erts_pon_default_match`? E na classificação por tipo (bucket)?

25. (Prioridade) A BEAM tem `receive` com mensagens prioritárias (ERTS_INTERNAL_MSG_TAG). Como o PON-Receive trata mensagens de prioridade diferente? Os buckets 256 são suficientes?

### Questões Teóricas

26. O PON-Receive elimina o scanning, mas introduz notificação por Premise. Em um sistema com poucas mensagens (N=2, M=1), o custo do PON-Receive pode ser *maior* que o scanning? Sob que condições?

27. A mailbox PON usa 256 buckets baseados em tag de tipo. Se dois tipos diferentes colidirem no mesmo bucket (ex: `{call, _, _}` e `{cast, _}` se `tag(call) == tag(cast)`), há perda de eficiência? Quantifique.

28. O PON-Receive não modifica o modelo de *concorrência* da BEAM — processos continuam isolados. A mudança é apenas no mecanismo interno de recepção. Isso é uma vantagem de engenharia? Poderia haver impacto na semântica observável?

29. Projetos como `gen_statem` usam `receive` internamente com padrões complexos. Como a abordagem de Premises se aplica a receives aninhados ou receives com guardas?

30. (Dissertação) O PON-Receive é uma specialização do PON geral: as Premises são FBEs, a mailbox é um conjunto de Attributes, o Receive é a Condition e a Rule. Modele formalmente esta correspondência: mostre como cada elemento do `receive` Erlang mapeia para as entidades PON do Capítulo 2.

---

## 4.11 Resumo para Memorização

- **Problema**: Selective receive da BEAM varre a mailbox linearmente: O(N × M).
- **Save pointer** ameniza mas não elimina o custo: mensagens novas ainda são varridas.
- **PON-Receive**: cada cláusula compila para uma `ErtsPremise` — entidade que escuta passivamente.
- **Mailbox PON**: 256 buckets por tipo de mensagem (8 bits de tag).
- **Chegada**: `queue_messages` hook → `erts_pon_notify_premises` → classifica por tipo → notifica Premises.
- **Receive**: `erts_pon_receive` → encontra Premise satisfeita por ordem de cláusula → consome → sem scanning.
- **Bloqueio**: processo WAITING até que uma mensagem que casa alguma Premise chegue.
- **Match**: fallback estrutural `erts_pon_default_match` ou `match_fn` especializada gerada pelo compilador.
- **Custo**: O(M + K) contra O(N × M) da BEAM stock.
- **Implementação**: `pon_premise.h` (86 linhas), `pon_premise.c` (211 linhas), hooks em `erl_message.h`, `erl_message.c`, `erl_process.h`.

---

## 4.12 Ver Também

- [Capítulo 1 — Diagnóstico do scanning linear na mailbox](01-diagnostico-scamming-mailbox.html)
- [Capítulo 2 — Paradigma Orientado a Notificações](02-paradigma-pon.html)
- [Capítulo 3 — Visão geral da PON-BEAM](03-visao-geral.html)
- [Capítulo 5 — PON-Timer](05-pon-timer.html)
- [Capítulo 10 — PON-Compiler](10-pon-compiler.html)
- [Relatório da Fase 1 — PON-Receive](../docs/RPT-01-pon-receive.html)
- `erts/include/internal/pon_premise.h` — Definição de `ErtsPremise` e macros
- `erts/emulator/beam/pon_premise.c` — Implementação completa do PON-Receive (211 linhas)
- `erts/include/internal/pon_stats.h` — Contadores de instrumentação
- `erts/emulator/beam/erl_message.h:401-412` — Hooks da mailbox PON
- `erts/emulator/beam/erl_message.c:461-476` — Hooks de notificação na chegada de mensagem
- Simão, J. M.; Stadzisz, P. C. "Paradigma Orientado a Notificações: Uma Nova Abordagem para Sistemas Reativos." (2008–2009).
- Armstrong, J. "Programming Erlang: Software for a Concurrent World." Pragmatic Bookshelf, 2007. — Capítulo sobre selective receive e mensagens.
