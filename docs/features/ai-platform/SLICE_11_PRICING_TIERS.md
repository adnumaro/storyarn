# Slice 11 — Pricing, Tiers & Credit Purchase (data-driven)

## Objective

Turn measured telemetry (Slices 2 + 6–10) into the commercial layer: per-plan monthly credit grants, credit top-up purchases, per-action published prices, spend visibility for users/workspaces, and budget alerts — WITHOUT locking tier numbers before the data exists.

## Problem & proposed solution

**Problem:** pricing before measurement is a bet (planning doc §9). We need real answers first: cost per feature, cost per average user, margin per tier, % of MRR on inference, acceptance rates per tool.
**Solution:** this slice runs in two stages. **Stage A (analysis, no code):** a pricing memo from `ai_usage_events` — proposed grants per tier (Free/Creator/Pro/Studio sketch from the planning discussion), per-action prices with the 2.5–4× multiplier, ≤10–20%-of-net-revenue check. Owner signs off the memo. **Stage B (implementation):** grants, purchases, dashboards, alerts per the approved memo.

## Architectural direction

- Extend `Storyarn.Billing`: `Plan` gains `monthly_ai_credits`; `Limits` gains AI-credit checks following its existing `can_*?` query pattern; grants run as an Oban cron (monthly reset — grants expire, purchased credits policy per memo).
- Purchases through the EXISTING billing/subscription machinery — audit what `Billing`/`SubscriptionCrud` already integrate (Stripe or not) during Stage A; do not introduce a second payment path.
- Spend UI: user-level (settings, next to the Slice-2 balance) and workspace-level (owner view) using the dashboard shell components; per-member/project breakdown for Studio-tier pool visibility (pool itself may defer — memo decides).
- Anomaly/budget alerts: threshold checks post-metering (Slice-2 `Budget` post-stage) → email via existing mailer patterns + in-app flash/notification.
- Tier gating semantics: task scope and volume only — NEVER silent quality degradation of the same task (OVERVIEW guardrail).

## Existing code to reuse (do not duplicate)

`Storyarn.Billing.{Plan, Subscription, SubscriptionCrud, Limits}` · Slice-2 `Credits` ledger (purchase = one more append-only entry type) + `Metering` · Oban cron (existing crontab config pattern) · dashboard shell: **`assets/app/shell/DashboardContent.vue` is the only shell component verified on `main` — re-check what exists at implementation start; if stat-card/panel shells are still absent, create them under `shell/` (component-registry check first) rather than bespoke layouts** · `StoryarnWeb.Live.Shared.DashboardHelpers` · `Shared.TimeHelpers` · mailer/`Emails` patterns for alerts · PostHog events for funnel analysis.

## Applicable conventions (MUST be surfaced in chat during implementation)

Billing changes through the `Billing` facade · DB-enforced ledger integrity (no negative balances via constraint/transaction, mirror Slice-2 design) · `dgettext("settings", …)` / dashboard i18n en/es · authorization: workspace spend views gated by `:manage_workspace`; user spend by own scope · dashboards via the shared Vue shells (no bespoke layouts) · pricing copy reviewed by owner before merge (user-facing money text is owner-approved, not implementer-invented).

## Observability & error handling

Purchase failures surface the payment provider's error explicitly (no optimistic credit before confirmation) · grant cron emits a missed-grant alert if a period has no grant row for an active workspace · spend-anomaly alerts (already specified) reach the owner, not just logs · dashboards read from `ai_usage_events`/ledger only — no shadow counters · user docs: pricing/credits pages ship WITH Stage B (owner-approved copy), flag-hidden until GA.

## Verification / Definition of Done

- Stage A: pricing memo delivered and approved in chat (blocker for Stage B).
- ExUnit: grant cron (idempotent per month), purchase entries, limit checks per tier, alert thresholds.
- Vitest: spend dashboards, top-up flow UI.
- Browser: full loop — consume credits, hit limit, top up, verify grant reset on simulated month roll.
- `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-pricing-tiers` from main → PR. Flag: `:ai_integrations` — the single AI flag governs commercial surfaces too; staged commercial rollout, if needed, uses per-actor targeting of the SAME flag (FunWithFlags actors), never a second flag.

## Inputs from previous slices

Slice 2 (ledger/metering — hard dependency) + REAL usage telemetry from Slices 6–10 in beta (Stage A needs weeks of data; do not start Stage A the day Slice 10 merges). Estimate: **8–12h** implementation + analysis time.
