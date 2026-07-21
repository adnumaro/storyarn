# Slice 2 — AI Service Core + Internal Provider + Credits

## Objective

`Storyarn.AI.execute/1` as the single task-based entry point for platform-paid inference: task registry, model router (v0: one managed open-weight provider), usage metering with real cost, credit ledger with monthly grants, and budget gates before/during/after every call. User-visible proof: credit balance in settings + one micro-task ("Summarize this flow") runnable end-to-end.

## Problem & proposed solution

**Problem:** turning a variable, unpredictable inference cost into a feature with controlled margin — without coupling Storyarn to any provider, and without users thinking in tokens/keys.
**Solution:** the app requests tasks, never models: `AI.execute(%{task: :summarize_flow, scope: …, quality: :standard})`. A router picks provider+model per task tier; metering records tokens/cost/credits/latency per call; a ledger enforces balances. Budget model is **reserve → call → settle**: credits are atomically reserved BEFORE the provider call (not merely estimated), the call runs under output caps/timeouts/bounded retries, and afterwards the reservation is settled to real cost — unused amount refunded, overrun recorded and capped. A crash between call and settlement leaves a reservation that a sweeper settles from the metering row (never a silent free call, never a double charge).

## Architectural direction

- Extend the existing `Storyarn.AI` facade (Slice 0) with submodules: `TaskRegistry` (task defs: quality tier, max output tokens, credit price, output schema) · `Router` (task tier → provider+model; v0 trivial single provider, interface ready for cheap/standard/premium) · `Providers.Internal` (managed open-weight; OPEN decision Together/Cloudflare in OVERVIEW) · `Metering` · `Credits` · `Budget`.
- **New behaviour** `Storyarn.AI.InferenceProvider` (`generate/2` with structured request/response incl. token usage) — the Slice-0 `Provider` behaviour (metadata + validate_key) stays as-is for BYOK connection management; internal provider implements BOTH lanes' contracts where applicable.
- Migrations: `ai_usage_events` (user/workspace/project, feature, provider, model, input/cached/output tokens, provider_cost_usd, credits_charged, latency_ms, succeeded) · `ai_credit_ledger` — append-only entries (`monthly_grant | reservation | settlement | refund | purchase`) with:
  - **explicit owner scope** on every row (OPEN decision in OVERVIEW: recommendation is workspace-scoped to match Billing plans, per-member attribution via usage events) — `execute/1` receives and validates that scope; no ambient/default owner;
  - **grant period + expiry** columns and a **DB-unique idempotency key** per (owner, period) so a retried monthly grant cannot double-credit and expired grants cannot accumulate;
  - **defined consumption order** at debit time (expiring credits first, then purchased);
  - **concurrency-safe debits**: reservation acquires a lock on a stable credit-owner row (or equivalent atomic conditional insert) so two concurrent reservations cannot both pass the balance check — derived-balance-in-a-transaction alone does NOT serialize read-then-insert; plus an idempotency key per request so client/Oban retries never charge twice. Covered by dedicated concurrency tests.
- **`execute/1` result contract**: every call persists an `ai_operations` row (`queued | running | succeeded | failed`) keyed by an idempotent operation id. Short tasks return `{:ok, result}` inline (operation recorded as succeeded); long tasks return `{:async, operation_id}` and complete via Oban — retries are idempotent against the operation id (settlement happens once), results/failures observable by polling or PubSub on the operation.
- Privacy default: metering stores counts and costs, **never prompt/response content**.
- Long tasks run through Oban (new `ai` queue); short tasks inline. Telemetry: extend `[:ai, …]` event namespace from Slice 0.
- Flag: `:ai_platform` for all credit-lane surfaces (OPEN decision).

## Existing code to reuse (do not duplicate)

From Slice 0 (requires PR #28 merged): `Storyarn.AI` facade · `Providers` registry (internal = one more adapter) · `KeyValidation` classify patterns · `Audit` · `Runtime.with_integration/3` (BYOK lane untouched) · `FeatureFlags` · Req + `Req.Test` config pattern (`req_options` per adapter).
Global: `Shared.TimeHelpers` · `Shared.MapUtils` · `Storyarn.RateLimiter` (new bucket for execute calls) · Oban (queues config in `config.exs`) · `Billing.Limits` (pattern reference for limit checks; integration itself is Slice 7) · `config/runtime.exs` secret pattern for `INTERNAL_AI_API_KEY` · telemetry span pattern from `Runtime`.

## Applicable conventions (MUST be surfaced in chat during implementation)

Context facade + `defdelegate`; LiveViews never call submodules · CRUD/changeset templates (`docs/conventions/domain-patterns.md`) · DB-enforced integrity over CRUD-level trust (ledger constraints, append-only where applicable — mirror the Slice-0 audit trigger approach) · `with_authorization` on every mutating LV event · `dgettext` for all user-facing text (decide domain: extend "integrations" vs new "ai" — surface in chat) · migrations: fresh, no back-compat shims (pre-release), verify dev DB after edits · shared-utilities registry check before ANY helper.

## Verification / Definition of Done

- ExUnit: TaskRegistry, Router, Internal provider (Req.Test), Credits (grant idempotency per period, expiry, consumption order, reserve/settle/refund, insufficient balance, **concurrent reservations cannot overdraw**), Budget gates (reservation precedes call, output caps enforced, orphaned-reservation sweeper), `ai_operations` states + retry idempotency (no double charge), Metering rows, execute inline + async paths.
- Vitest: credit balance UI, summarize-flow surface.
- Browser: run the micro-task on a real flow with the flag enabled; watch balance decrease; verify metering row.
- `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-service-core` from main → PR → merge before Slice 3. Flag `:ai_platform` disabled by default.

## Inputs from previous slices

Slice 0 merged (facade, registry, flags, audit, telemetry naming). Estimate: **12–16h**.
