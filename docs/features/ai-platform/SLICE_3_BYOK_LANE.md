# Slice 3 — BYOK Lane Through the AI Service + Limit Fallback UX

## Objective

AI Service tasks can run on the user's own connected keys: `InferenceProvider` implementations for the BYOK providers, lane resolution in the Router (`internal_first` with consented fallback | `byok_only`), the at-limit fallback UX (first-time opt-in per provider + persistent setting + provenance badges), and `lane` recorded on every usage event. BYOK-lane calls debit no credits.

## Problem & proposed solution

**Problem:** hitting the credit limit dead-ends the user mid-work, and BYOK-only features (Slices 9–10) have no execution path. Silent use of a user's external key would spend their money without consent.
**Solution:** implement the owner-decided lane routing policy (OVERVIEW): at the limit, a banner offers credit top-up (when Slice 11 ships; hidden until then) AND "continue with your own key". First-time fallback per provider requires an explicit opt-in modal ("billed to your account"); consent persists as a toggle on the integrations page. Every result shows its lane badge; usage events carry `lane`; BYOK calls are metered (tokens/latency/success) but never debited.

## Architectural direction

- Router (Slice 2) gains lane resolution: task policy (`internal_first` | `byok_only`) × user state (balance, connected providers, consent) → lane. No new entry point — `AI.execute/1` callers are lane-agnostic.
- **Capabilities model introduced here**: provider metadata gains an immutable `capabilities` list (see OVERVIEW lane policy §5) — consumed by lane resolution, Slices 4/9/10, and the connect-CTA logic. Until Slice 4 assignments land (one slice later), BYOK provider selection is "the single/first capable connected provider".
- BYOK execution reuses `Runtime.with_integration/3` (Slice 0) for key checkout — auto-revoke on 401/403, `last_used_at`, telemetry are already built; the lane wraps the `InferenceProvider` call inside it.
- `InferenceProvider` implementations: one OpenAI-compatible chat adapter shared by OpenAI/Moonshot/Mistral/DeepSeek (base URL + auth from each provider's metadata) + dedicated Anthropic (Messages API) and Google (generateContent) adapters. All test-injectable via the existing `req_options` pattern.
- Consent: per (user, provider) columns on the existing `ai_integrations` row (e.g. `fallback_consented_at`) — no new table; toggle rendered in the integrations settings page.
- At-limit banner + opt-in modal: LiveView-driven, reusing the flash/banner patterns; provenance badge is a small shared Vue component used by every AI result surface.

## Existing code to reuse (do not duplicate)

Slice 0: `Runtime.with_integration/3` · `Providers` registry + per-provider metadata · `KeyValidation`/`req_options` test pattern · integrations settings page (toggle lands there) · `Audit`. Slice 2: Router, `TaskRegistry`, `Metering` (+`lane` field), `ai_operations`, Budget (limit detection). Global: `FeatureFlags`, `Storyarn.RateLimiter`, `ConfirmDialog.vue` (opt-in modal base), gettext/i18n infra.

## Applicable conventions (MUST be surfaced in chat during implementation)

No silent spending of user money — consent is a hard gate, tested · facade-only exposure · authorization on the consent toggle event (own scope) · i18n en/es for banner/modal/badges · migration adds columns to `ai_integrations` (verify dev DB after edit) · Lucide icons · component registry check before the badge component.

## Verification / Definition of Done

- ExUnit: lane resolution matrix (balance × connected × consent), consent gate blocks fallback without opt-in, BYOK calls debit zero credits but write metering rows with `lane`, OpenAI-compatible adapter against Req.Test for all four providers, Anthropic/Google adapters, auto-revoke path still fires through the lane.
- Vitest: opt-in modal, integrations toggle, provenance badge states.
- Browser: force the limit (test fixture/flag), walk the consent flow with a real key, verify badge + no credit debit.
- Lint fix as last command before push · `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-byok-lane` from main → PR → merge before Slice 4. Flag `:ai_platform`.

## Inputs from previous slices

Slices 0 and 2 merged. Estimate: **10–14h**.
