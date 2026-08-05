/* pon_acsl.h — Frama-C ACSL Contract Annotations for PON-BEAM ERTS C Functions */
#ifndef PON_ACSL_H
#define PON_ACSL_H

#include <stddef.h>
#include <stdbool.h>

typedef struct {
    int id;
    int state;
    void* payload;
} PonPremise;

typedef struct {
    int condition_id;
    PonPremise* ready_head;
    int pending_count;
} PonCondition;

#define PON_PREMISE_WAITING   0
#define PON_PREMISE_SATISFIED 1

/*@
  @ requires \valid(c);
  @ assigns \nothing;
  @ ensures \result == true || \result == false;
  @*/
bool erts_pon_condition_is_ready(const PonCondition* c);

/*@
  @ requires \valid(p);
  @ requires \valid(c);
  @ requires p->state == PON_PREMISE_WAITING;
  @ assigns  p->state, c->ready_head, c->pending_count;
  @ ensures  p->state == PON_PREMISE_SATISFIED;
  @ ensures  c->pending_count == \old(c->pending_count) + 1;
  @ ensures  c->ready_head == p;
  @*/
void erts_pon_schedule_notify(PonPremise* p, PonCondition* c);

/*@
  @ requires \valid_read(p);
  @ assigns  \nothing;
  @ ensures  \result == (p->state == PON_PREMISE_SATISFIED);
  @*/
bool erts_pon_premise_is_satisfied(const PonPremise* p);

#endif /* PON_ACSL_H */
