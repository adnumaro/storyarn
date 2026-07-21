# Slice 3 — BYOK Lane Through the AI Service + Limit Fallback UX

## Objective

AI Service tasks can run on the user's own connected keys: `InferenceProvider` implementations for the BYOK providers, lane resolution in the Router (`internal_first` with consented fallback | `byok_only`), the at-limit fallback UX (first-time opt-in per provider + persistent setting + provenance badges), and `lane` recorded on every usage event. BYOK-lane calls debit no credits.

## Problem & proposed solution

**Problem:** hitting the credit limit dead-ends the user mid-work, and BYOK-only features (Slices 9–10) have no execution path. Silent use of a user's external key would spend their money without consent.
**Solution:** implement the owner-decided lane routing policy (OVERVIEW): at the limit, a banner offers credit top-up (when Slice 11 ships; hidden until then) AND "continue with your own key". First-time fallback per provider requires an explicit opt-in modal ("billed to your account"); consent persists as a toggle on the integrations page. Every result shows its lane badge; usage events carry `lane`; BYOK calls are metered (tokens/latency/success) but never debited.

## Architectural direction

- Router (Slice 2) gains lane resolution: task policy (`internal_first` | `byok_only`) × user state (balance, connected providers, consent) → lane. No new entry point — `AI.execute/1` callers are lane-agnostic. **Lane branching happens BEFORE budget reservation: a `:byok` execution never touches the credit ledger — no reservation, no settlement, no refund rows — it writes metering only** (explicit no-ledger-mutation test).
- **Operations carry their lane**: `ai_operations` persists `lane` + resolved provider so async result surfaces render the provenance badge without guessing, and every operation associates to its usage event. `ai_usage_events` gains a **constrained `lane` column via migration** (verified against the dev DB) — the lane audit trail is schema-enforced, not an in-memory field.
- **Capabilities model introduced here**: provider metadata gains an immutable `capabilities` list (see OVERVIEW lane policy §5) — consumed by lane resolution, Slices 4/9/10, and the connect-CTA logic.
- **BYOK target = the user-marked DEFAULT AI only (owner-decided — no "first capable connected" auto-pick)**: the first-time at-limit opt-in modal doubles as default designation ("continue with your X account" marks X as your default, with the explicit hint "this is the model used when you hit the platform AI limit"). No consented default → explicit error + CTA (at the limit, the opt-in modal IS that CTA). Slice 4 adds the management UI for changing the default.
- BYOK execution reuses `Runtime.with_integration/3` (Slice 0) for key checkout — `last_used_at` and telemetry are already built; the lane wraps the `InferenceProvider` call inside it. **Auto-revocation narrows here: only adapter-classified credential-invalid responses (401, plus 403s the provider explicitly signals as an invalid/revoked key) revoke the integration; permission- or capability-specific 403s surface as request errors and leave the key intact** — a valid key must never be revoked because one model or endpoint was forbidden.
- `InferenceProvider` implementations: one OpenAI-compatible chat adapter shared by OpenAI/Moonshot/Mistral/DeepSeek (base URL + auth from each provider's metadata) + dedicated Anthropic (Messages API) and Google (generateContent) adapters. All test-injectable via the existing `req_options` pattern.
- Consent: `fallback_consented_at` lives ON the `ai_integrations` row — **binding consent to the key's lifecycle by construction**: disconnect+reconnect creates a NEW integration row (Slice 0 design), so a rotated or newly connected key always starts unconsented and requires a fresh opt-in before automatic fallback can spend from it (reconnect path explicitly tested). Toggle rendered in the integrations settings page.
- At-limit banner + opt-in modal: LiveView-driven, reusing the flash/banner patterns; provenance badge is a small shared Vue component used by every AI result surface.

## Existing code to reuse (do not duplicate)

Slice 0: `Runtime.with_integration/3` · `Providers` registry + per-provider metadata · `KeyValidation`/`req_options` test pattern · integrations settings page (toggle lands there) · `Audit`. Slice 2: Router, `TaskRegistry`, `Metering` (+`lane` field), `ai_operations`, Budget (limit detection). Global: `FeatureFlags`, `Storyarn.RateLimiter`, `ConfirmDialog.vue` (opt-in modal base), gettext/i18n infra.

## Applicable conventions (MUST be surfaced in chat during implementation)

No silent spending of user money — consent is a hard gate, tested · facade-only exposure · authorization on the consent toggle event (own scope) · i18n en/es for banner/modal/badges · migration adds columns to `ai_integrations` (verify dev DB after edit) · Lucide icons · component registry check before the badge component.

## Observability & error handling

Lane decision recorded on the operation and usage event · consent-missing and default-missing are explicit errors with CTA (never an auto-picked provider) · provider errors classified: credential-invalid (revokes) vs capability/permission (request error, key intact) · **provider-failure alert contract: ≥5 classified failures for the same provider within a 10-minute window (initial values, owner-tunable) emits one deduplicated alert per provider per window, tagged with provider + failure classification** · PostHog events (via the `Storyarn.Analytics` allowlist, added with tests): `ai_limit_banner_shown`, `ai_limit_topup_clicked`, `ai_limit_byok_chosen` (provider) · user docs: at-limit behavior + consent + provenance badges documented in the flag-hidden AI docs.

## Verification / Definition of Done

- ExUnit: lane resolution matrix (balance × connected × consent), consent gate blocks fallback without opt-in, **reconnected key requires fresh consent (old row's consent never carries over)**, **`:byok` executions mutate zero ledger rows (no reservation/settlement/refund) while writing metering with `lane`**, `lane` column present and constrained in the DB, `ai_operations` carries lane/provider for async badge rendering, OpenAI-compatible adapter against Req.Test for all four providers, Anthropic/Google adapters, **revocation classification: credential-invalid revokes; capability/permission 403 returns a request error and leaves the integration intact**.
- Vitest: opt-in modal, integrations toggle, provenance badge states.
- Browser: force the limit (test fixture/flag), walk the consent flow with a real key, verify badge + no credit debit.
- Lint fix as last command before push · `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-byok-lane` from main → PR → merge before Slice 4. Flag: `:ai_integrations` (the single AI flag).

## Inputs from previous slices

Slices 0 and 2 merged. Estimate: **10–14h**.
