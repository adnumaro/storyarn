# Slice 9 — Tiptap Writing Suggestions (manual, BYOK-only)

## Objective

Manual-trigger writing suggestions in tiptap-based rich-text editors: the user hits a shortcut/button, gets ghost-text continuation grounded in the surrounding text and entity context, and accepts (insert) or dismisses. **BYOK-only** and **manual-only** per the lane routing policy (owner-decided). Acceptance telemetry on every suggestion.

## Problem & proposed solution

**Problem:** the blank-page moment is the most common writing friction — but continuous auto-suggest is the most expensive per-user AI pattern (unbounded frequency), which is exactly why it cannot run on platform credits.
**Solution:** suggestions are explicit, single-shot, and run on the user's key through the Slice-3 lane, resolved via the **Writing-assistant assignment (Slice 4)**. Trigger → bounded context assembled (surrounding document segment + relevant entities via Slice 5) → one `AI.execute(:writing_suggestion, lane: :byok_only)` call → ghost text rendered inline → Tab/click accepts (insert at cursor + acceptance event), Esc dismisses (dismissal event). **Every suggestion reaches a terminal acceptance outcome: accepted | dismissed | abandoned (cancelled/re-triggered/blurred, recorded as a dismissal reason per the Slice-7 schema) — so the acceptance-rate denominator reconciles 1:1 with metered calls.** Users without a connected key see the connect CTA instead of the trigger affordance.

## Architectural direction

- Tiptap extension in the existing plugin structure (`assets/app/plugins/tiptap/`): decoration-based ghost text (never real document content until accepted — undo history stays clean), keyboard handling scoped to the ghost state (Tab/Esc), single in-flight request. **Cancellation is honestly scoped: re-trigger/blur suppresses the RESULT (stale-response guard by request token) — it does NOT abort the provider call in v1, so an abandoned suggestion still completes and bills the user's account (one small, output-capped call). Aborting mid-flight through `AI.execute`/`InferenceProvider` is deliberate non-scope; revisit only with evidence of waste.**
- Trigger surfaces: editor keyboard shortcut + a toolbar affordance in editors that have one. Registered as a palette command too where an editor has focus (Slice 1 registry).
- Context: the containing block/field text around the cursor plus scoped entity context from `build_context` (Slice 5; e.g. the sheet the rich-text block belongs to). Hard input budget — this is a cheap, fast task by design.
- Rate limiting server-side per user (protects the user from their own trigger-spam against their provider bill) via the existing `RateLimiter` pattern.
- No-BYOK state: affordance renders as a connect CTA deep-linking to the integrations page. Feature invisible when the `:ai_integrations` flag is off.

## Existing code to reuse (do not duplicate)

`assets/app/plugins/tiptap/` extension structure + existing editor components · Slice-3 BYOK lane (`AI.execute` with `lane: :byok_only`, consent + badges) · Slice-4 `provider_for/2` (Writing-assistant assignment) · Slice-5 `build_context` (scoped, budget-bounded) · Slice-7 acceptance-event schema · `Storyarn.RateLimiter` (new bucket) · Slice-1 palette registration · `FeatureFlags` · gettext/i18n infra.

## Applicable conventions (MUST be surfaced in chat during implementation)

TypeScript strict, emits over callbacks · tiptap decorations for ghost text (no document mutation before accept) · `@keydown.stop` conventions respected around editor inputs · i18n en/es for CTA/affordances · Lucide icons · authorization: suggestion runs under the user's own scope; the editor's `can_edit` gates the trigger · component registry check before any new UI piece · acceptance events follow the Slice-5 schema, no parallel telemetry shape.

## Verification / Definition of Done

- Vitest: extension behavior (trigger renders ghost text, accept inserts + fires acceptance, dismiss clears + fires dismissal, re-trigger suppresses the stale result AND fires the abandoned terminal event, no ghost text in undo history).
- ExUnit: task def (`byok_only` lane enforced — no credit debit ever), context budget, rate-limit bucket, terminal-outcome events reconcile with metered calls (accepted/dismissed/abandoned cover 100%).
- Browser: real key, real editor — trigger, accept, dismiss, no-key CTA state.
- Lint fix as last command before push · `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-tiptap-suggestions` from main → PR. Flag: `:ai_integrations` (the single AI flag; the palette itself is unflagged).

## Inputs from previous slices

Slices 3, 4, 5 merged; Slice 7's acceptance schema. Estimate: **10–14h**.
