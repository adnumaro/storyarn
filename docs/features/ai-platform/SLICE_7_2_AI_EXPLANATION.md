# Slice 7.2 — Split Decision

**Status:** superseded by Slice 7.2a and Slice 7.2b before implementation.

## Decision

The original Slice 7.2 combined the first end-user AI task with a second
execution lane, a separate consent subsystem, and the public documentation
launch. Splitting by **execution lane** keeps each half independently
verifiable end to end:

| Slice | Product boundary                                                              | Lane            | Document                               |
| ----- | ----------------------------------------------------------------------------- | --------------- | -------------------------------------- |
| 7.2a  | Explain one selected finding through Storyarn AI, preflight to private result | `managed`       | `SLICE_7_2A_MANAGED_EXPLANATION.md`    |
| 7.2b  | Same task offered through the actor's own key, plus public AI documentation   | `personal_byok` | `SLICE_7_2B_PERSONAL_LANE_AND_DOCS.md` |

Slice 7.2a must merge first. It registers the task, owns the panel operation
lifecycle, and establishes the preflight/result contract that Slice 7.2b
extends with a second explicit route. Slice 7.2b must not introduce a parallel
task, a second result surface, or any automatic lane substitution.

## Why the split runs along the lane, not the layer

- A backend/frontend split would leave neither half testable by a user. The
  lane split leaves 7.2a fully usable on its own: select a finding, see what is
  sent and what it costs, execute, read the explanation.
- Personal BYOK is a distinct subsystem, not a variation: capability-scoped
  consent, consent-version staleness, a separate personal operation, personal
  accounting, and per-provider structured-output contracts. It is the branch
  that most inflates the panel state machine.
- The palette command contract already models a deferred call to action
  (`availability: cta`), so adding the "Use my own API key" route in 7.2b is an
  extension of the existing preflight surface rather than a rewrite.
- Public documentation describes payer choice and BYOK billing. Publishing it
  before the personal lane exists would document half the product and require
  an amendment, so it ships with 7.2b.

## What does not change

Both halves keep the Slice 7.2 invariants: one operation explains exactly one
server-selected current finding; the client never authors finding or evidence;
the model returns bounded narrative only; deterministic facts and limitations
render separately from generated text; results are actor-private, temporary,
and never applied, attached, shared, or persisted as a report; and no silent
fallback, provider/model substitution, or payer change is ever performed.

This file is retained as a decision record and compatibility pointer. It is not
an implementation slice and does not receive its own branch or PR.
