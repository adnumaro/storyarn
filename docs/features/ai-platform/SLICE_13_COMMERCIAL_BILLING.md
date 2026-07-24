# Slice 13 — Commercial Billing + Paid AI Allowances

## Objective

Convert measured Storyarn AI usage into a commercial offering only after beta data demonstrates value and sustainable unit economics. Add payment-provider-backed subscriptions/entitlements first; top-ups and overages remain a later stage requiring separate demand and owner approval.

## Entry criteria

Do not start implementation immediately after the tool slices merge. Stage A requires several weeks of representative beta data and enough successful operations to answer:

- provider cost and cost per accepted/useful result by task;
- operations and allowance consumption per active workspace;
- managed-vs-BYOK choice and key-connection drop-off;
- reliability, abandonment, and acceptance by task/model;
- expected AI cost as a share of net plan revenue;
- demand for more allowance after exhaustion.

## Stage A — Pricing and payment decision memo

No product code. Owner approves:

- which subscription plans include Storyarn AI;
- monthly grant sizes and fixed task prices/size bands;
- grant reset/expiry and upgrade/downgrade behavior;
- target margin and safety buffer based on measured data;
- payment architecture: direct processor such as Stripe versus Merchant of Record;
- supported countries/currencies, tax responsibility, invoicing, refunds, chargebacks, and business-customer requirements;
- whether top-ups are justified. Default recommendation: subscriptions with included allowance first; top-ups deferred.

The existing `Storyarn.Billing` schemas are domain groundwork, not evidence that a payment path already exists.

## Stage B — Subscription billing and entitlements

- Integrate one payment provider; never store card data in Storyarn.
- Provider is source of truth for customer, subscription, invoice, payment, tax, and commercial status.
- Storyarn is source of truth for task prices, real-time allowance reservation, operations, technical refunds, and usage.
- Persist provider customer/subscription ids and an append-only, idempotent webhook inbox.
- Webhooks verify signatures, tolerate duplication/out-of-order delivery, and reconcile periodically.
- Subscription state maps to Storyarn plan/entitlements through the Billing facade.
- Monthly allowance grant is idempotent per workspace+billing period+pricing version.
- BYOK operations never consume paid allowance.
- Purchase/configuration actions require explicit workspace billing permission.

## Stage C — Optional top-ups/overages

This is not required for initial commercial launch. Add only with measured demand and an approved policy for:

- one-time payment and tax treatment;
- purchased-allowance expiry/non-expiry;
- allocation order between monthly and purchased grants;
- refunds/chargebacks after partial use;
- currency conversion and invoice representation;
- automatic top-up consent and spend ceilings.

## Pricing contract

- Managed tasks retain fixed, versioned user prices. Actual provider cost is internal margin telemetry and never retroactively changes a completed charge.
- Prices change only for new operations under a new pricing version.
- Context/internal helper calls are included in the task price.
- Size bands/caps make batch, image, and future managed speech costs bounded.
- Scope/volume may vary by plan; the same task is not silently degraded in quality.

## Spend UX and controls

- User view: allowance remaining, renewal date, task price, and own usage.
- Workspace owner view: grant/adjustments/usage by task/member/project plus actual-cost/margin health where appropriate.
- Explicit exhausted state: use personal BYOK, wait for renewal, or commercial CTA supported by the approved plan. No silent fallback.
- Durable cost/anomaly alerts use provider cost and margin ratio, not only allowance units charged.

## Existing code to reuse

`Storyarn.Billing.{Plan, Subscription, SubscriptionCrud, Limits}` · Slice-3 allowance ledger and metering · Oban/webhook/mailer/idempotency patterns · dashboard shells · authorization and audit helpers · payment provider SDK/HTTP integration chosen in Stage A.

## Non-goals

- Building a card processor, tax engine, or invoicing system in-house.
- Implementing multiple payment providers.
- Usage-based charging directly from raw model tokens.
- Top-ups before Stage C approval.
- Enterprise workspace BYOK vault or negotiated invoice contracts.

## Observability and error handling

- Payment events, grants, and provider webhooks have durable ids/idempotency keys and classified states.
- No optimistic allowance before confirmed entitlement/payment.
- Reconciliation detects missed webhooks/grants and alerts operators.
- Dashboards read canonical ledger/operation data, not shadow counters.
- Raw payment/provider errors and personal data never reach analytics/user copy.

## Verification / Definition of Done

- Stage A memo approved before implementation.
- ExUnit: webhook signature/idempotency/order, subscription→entitlement mapping, billing-period grants, upgrade/downgrade policy, payment failure, reconciliation, authorization, BYOK exclusion.
- Provider sandbox browser flow: subscribe, receive entitlement/grant, consume managed allowance, renew/cancel, verify exhausted choices.
- Tax/invoice/refund behavior verified against the approved provider/responsibility model.
- User pricing and billing copy explicitly approved.
- `just quality-lint` and full relevant suites green.

## Delivery

Stage A is a product/finance memo. Stage B uses branch `feat/ai-commercial-billing` from `main`. Stage C receives its own future branch/PR if approved. Commercial surfaces remain behind the existing entitlement/AI flag strategy during rollout.

## Inputs from previous slices

Slice 3 allowance/ledger plus representative production-like telemetry from Slices 7.2–12.
