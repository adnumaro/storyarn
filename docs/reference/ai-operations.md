# AI operations

> Owner: Engineering
>
> Last reviewed: 2026-07-29
>
> Source of truth: `config/runtime.exs`, `config/config.exs`, `lib/storyarn/ai/`, and `lib/storyarn/workers/`

This runbook describes the stable operating boundary for managed and personal
AI execution. Runtime configuration remains authoritative for provider, model,
prices, budgets, queues, cadences, retention, and enabled tasks.

## Activation

- Managed AI fails closed unless the global switch and the explicit
  zero-retention and no-training attestations are enabled.
- Managed provider, model, credential reference, region label, price snapshot,
  cost ceilings, and allowance price are validated at boot.
- Fireworks and Together are explicit managed-provider choices. There is no
  request-time provider, model, payer, or lane fallback.
- Personal BYOK providers use owner credentials and a versioned consent policy.
- A configured provider or capability does not expose a task. The task registry
  is the only execution catalog.

## Durable execution and accounting

- Operation creation, grants, reservations, commits, and releases are
  idempotent.
- Allowance ledger entries are append-only and content-free.
- Provider cost and product allowance are separate projections.
- A pre-attempt failure can release a reservation. After an external attempt,
  uncertain outcomes remain unknown until reconciled.
- Prompts and generated content do not belong in logs, analytics, alerts, or
  incident tickets.

## Queues and maintenance

- User-facing AI execution runs on the bounded `ai` queue.
- Reservation reconciliation and private-result expiry run on the independent
  `ai_maintenance` queue.
- Current cron and staging intervals live in `config/config.exs`; changing them
  requires re-evaluating recovery latency and database-compute cost together.
- Interrupted work must recover or terminalize without duplicating effects,
  allowance, or provider cost.

## Incident response

1. Disable managed AI and restart every node when the global route must close.
2. Pause a workspace allowance or managed policy for a scoped incident.
3. Inspect durable operation, usage, budget, allowance, ledger, and alert rows
   by operation ID.
4. Reconcile unknown external attempts with the provider before creating a new
   user intent.
5. Rotate managed credentials outside the database and restart.
6. Resolve alerts only after accounting is consistent; never edit ledger rows.

Before enabling a managed route, re-verify provider terms, processing claims,
the selected model contract, prices, cost ceilings, and operational recovery.
