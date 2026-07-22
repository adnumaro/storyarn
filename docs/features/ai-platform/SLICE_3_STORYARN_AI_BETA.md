# Slice 3 — Storyarn AI Beta + Internal Allowance

> Implementation status: complete on `codex/slice3-storyarn-ai-beta`; pending review/merge. Operator setup and reconciliation are documented in `STORYARN_AI_OPERATIONS.md`.

## Objective

Add the first managed execution lane: Storyarn owns the provider relationship and cost, users see **Storyarn AI**, and invited workspaces receive a small internal beta allowance. This slice validates real inference, cost controls, and failure accounting without checkout, subscriptions, top-ups, invoices, or a public pricing promise.

## Product model

Storyarn AI is the managed product layer — task definitions, narrative context, validation, permissions, proposals, provenance, and controlled execution — not a claim that Storyarn trained the underlying model.

During beta:

- one managed provider/model route is enabled at a time;
- grants are promotional internal units, not purchased value;
- task prices are fixed and versioned;
- provider cost is internal accounting and never changes the published task price;
- the Storyarn operator controls which actors/workspaces receive grants;
- no public user-facing AI task ships merely to demonstrate infrastructure; an operator-only diagnostic exercises the production provider until Slice 7/8 adds real tools.

## Allowance and ledger contract

- Workspace owns the managed allowance; every operation retains actor/project attribution.
- Managed execution requires the explicit `:use_ai` policy decision; bulk spend remains disabled until a later task declares and authorizes it.
- Allowance units are integer internal units. Provider cost uses `Decimal` and a provider-price snapshot.
- Ledger is append-only with grant, reserve, commit, release/refund, adjustment, and expiry entries linked to an operation.
- Reserve exactly the task's fixed price before the call; successful validated output commits exactly that price.
- A queued operation cancelled or deauthorized before provider access releases its reservation. After an external attempt starts, Slice-2 forbids `cancelled`: a known outcome settles as success/failure, while an unprovable outcome becomes `unknown`.
- Confirmed provider failure, timeout, invalid structured output, or `unknown` outcome releases the user reservation. Storyarn absorbs any external cost already incurred.
- A valid result dismissed by the user remains charged.
- Grants may be configured as one-time or periodic beta allowances. Values and expiry are Storyarn-operator configuration, not hard-coded commercial promises.
- The execution-time balance is Storyarn's source of truth; no external billing system participates.

## Managed provider contract

- Managed providers live in a registry separate from Slice-0 connectable providers.
- Initial candidate: Together.ai only after contractual/operational verification of the required ZDR and EU-region configuration. Failure to prove or configure either keeps the lane disabled and returns the choice to the Storyarn operator.
- Region is derived from trusted deployment/workspace policy, never client input.
- Provider/model selection is configured behind the route contract so consumers never change when the vendor changes.
- No automatic inference retries.
- Provider request ids are persisted when available for reconciliation.

## Budget and abuse controls

- Global daily/monthly provider-cost ceilings.
- Per-workspace allowance and per-user/task rate limits.
- Hard input/output caps from TaskRegistry.
- Concurrency limit on the `ai` Oban queue.
- Operational task/provider enablement and manual circuit breakers; these are not additional product feature flags.
- Durable alerts for allowance anomalies, provider-cost spikes, and unresolved `unknown` operations.

## User experience

- Lane badge: `Storyarn AI` with provider/model available in provenance details.
- Workspace owner settings expose the Slice-2 managed-lane policy control through the existing owner-only `:manage_workspace` path. It defaults off; enabling it shows the Storyarn AI data-egress/provider-region disclosure, records an audited policy-version change, and never enables personal BYOK.
- Admins and members can see whether workspace policy permits Storyarn AI, but only the owner can change it in v1; the flag, policy, `:use_ai`, task availability, and allowance must all pass independently.
- Settings may show beta allowance and recent managed usage once a real user-facing task exists.
- When allowance is unavailable, return a classified blocked state. Slice 4 may offer personal BYOK as an explicit choice; this slice does not silently route there.
- User-facing copy calls the balance and task cost “AI allowance” / “allowance units” during beta, never credits, wallet, or purchased balance.

## Existing code to reuse

Slice-2 execution kernel/TaskRegistry/operations · `Storyarn.Billing` value objects only where useful, without pretending a payment processor exists · Oban · `Storyarn.RateLimiter` · settings/dashboard shell components · telemetry and mailer/notification patterns · Req/Req.Test provider patterns.

## Non-goals

- Paid plans, checkout, stored payment methods, invoices, tax, or top-ups.
- Workspace BYOK/service-account credentials.
- Multi-model quality tiers or self-hosting.
- Automatic managed→personal fallback.
- Public prices or final grant sizes.
- A throwaway “summarize flow” product surface.

## Observability and error handling

- Record fixed allowance units charged separately from actual provider cost.
- Track provider/model, token counts, latency, result validation, and reliability without content.
- Every reserve reaches a durable commit or release; a sweeper alerts and releases stale reservations without retrying an unknown provider call.
- Provider/configuration failures are explicit and localized.

## Verification / Definition of Done

- ExUnit: managed policy defaults off; only the workspace owner can enable it through `:manage_workspace`; admin/member read-only behavior; policy/version and `:use_ai` enforcement; exact fixed-price reserve/commit; releases for technical/validation/unknown failure; dismissal remains charged; concurrent balance safety; idempotent grants; grant expiry; global/workspace caps; circuit breakers; no BYOK ledger mutation.
- Provider contract tests with Req.Test plus one Storyarn-operator-run real diagnostic in the configured EU/ZDR environment.
- Browser: flagged owner can enable the managed policy and sees Storyarn AI provenance and allowance/blocked states through a diagnostic or first available task shell; admin/member cannot change policy; no payment or “credits” CTA/copy exists.
- Cost/reconciliation runbook documented.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/storyarn-ai-beta` from `main` → PR → merge before Slice 4. Keep `:ai_integrations` Storyarn-operator/invite-only.

## Inputs from previous slices

Slice 2 execution kernel and Slice 0 feature-flag/provider conventions.
