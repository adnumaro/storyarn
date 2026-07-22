# Slice 11 — Manual Tiptap Writing Suggestions

## Objective

Offer explicit, single-shot ghost-text continuation in a small, enumerated set of editable Tiptap surfaces. V1 is personal-BYOK-only and manual-only to keep frequency, cost, privacy, and editor behavior understandable.

## Supported-surface contract

Before implementation, inventory and name the exact editors/fields that can support insertion safely. Each surface declares:

- how the current document/cursor selection is captured;
- permitted surrounding-text window and locale;
- insertion schema/markup rules;
- whether Tab is available or another accept binding is required;
- required project/entity permission;
- toolbar and contextual palette affordances.

Unsupported editors do not register the command.

## User flow

- Manual shortcut/button/palette command captures the current editable selection before focus changes.
- Show `{Provider} · your key`, capability-scoped consent, and external-billing disclosure.
- Build bounded context from the local document segment plus only task-declared entity fields from Slice 6.
- One operation/provider call returns a decoration-based ghost suggestion.
- Accept inserts through the editor command and normal undo history; dismiss removes the decoration; no document mutation occurs before accept.
- Re-trigger creates a deliberate new operation. A successful suggestion already presented to the user becomes `user_disposition = dismissed` with reason `regenerated`; a successful result superseded before it was ever presented becomes `user_disposition = abandoned` with reason `retriggered`. An in-flight provider call may still finish and remain billed.

## Execution semantics

- Task lane is `personal_byok` only; no Storyarn allowance or automatic fallback.
- Single in-flight request per editor; stale response tokens suppress obsolete UI.
- Closing/blur does not claim to abort the external provider call.
- `execution_status` can succeed while `user_disposition` later becomes abandoned; provider failure remains a technical failure and is not overwritten by blur.
- No automatic retry or continuous background generation.
- Server-side per-user/surface rate limits and hard input/output caps.

## Command palette

The Slice-2 editable-context shortcut and async contract are hard prerequisites. This is palette v2 `execute`, not `launch`: it is visible only for a focused supported editor, captured valid selection, `:use_ai` plus `:edit_content`, a current server-issued personal `requested_route_ref`, consent, and workspace egress permission. Missing route/consent returns a repair CTA rather than starting an operation. Destination is `inline_editor`.

## Existing code to reuse

Existing Tiptap plugin/extension architecture and editor commands · current rich-text serialization/validation · Slice-2 operations/palette v2 · Slice-4 BYOK/consent · Slice-5 Writing-assistant preference · Slice-6 bounded context · `Storyarn.RateLimiter` · i18n and Lucide conventions.

## Non-goals

- Continuous/copilot-style auto-suggest.
- Managed Storyarn AI allowance.
- Unsupported editors or arbitrary HTML insertion.
- Whole-document context.
- Provider-call cancellation claims.
- Automatic acceptance or rewriting existing content.

## Observability and error handling

- Record task/surface, size, latency, provider/model, execution status, and disposition without editor content.
- Accept/dismiss/abandon reasons are product events linked to the operation.
- Provider, consent, rate-limit, schema, stale-selection, and editor-insertion errors are explicit and localized.

## Verification / Definition of Done

- Unit/Vitest per supported editor: trigger, decoration, accept insertion+undo, dismiss, re-trigger/stale suppression, blur semantics, Tab/key conflict, no pre-accept mutation.
- ExUnit: BYOK-only/no ledger rows, policy/permission, context caps, rate limits, operation status vs disposition, no retry.
- Palette/browser: open from supported contenteditable despite Tiptap key handling; unsupported surfaces remain absent; real-key accept/dismiss path.
- User docs list supported editors, shortcuts, billing, and cancellation semantics.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/ai-tiptap-suggestions` from `main` → PR. Flag: `:ai_integrations` plus operational task switch.

## Inputs from previous slices

Slices 2, 4, 5, and 6 plus existing Tiptap/editor contracts.
