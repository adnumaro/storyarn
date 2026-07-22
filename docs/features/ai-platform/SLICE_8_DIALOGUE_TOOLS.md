# Slice 8 — Dialogue Rewrite + Variants

## Objective

Let an editor rewrite one selected dialogue/response or generate a small set of variants using Storyarn AI or personal BYOK, compare them against the current text, and apply one through the existing mutation path with stale-write protection.

## Product contract

- One selected dialogue/response and one explicit output locale per operation.
- Context is bounded to the selected text, speaker fields allowed by the task, and narrowly declared incoming condition/variable evidence. Never send the whole flow.
- The exact context manifest, lane, provider/model, and managed price or BYOK payer are disclosed before generation.
- Generated variants are private to the actor until one is applied or deliberately shared.
- Model output is a proposal; it never mutates project state directly.
- Generation requires both `:use_ai` and `:edit_content` for the selected project entity; Apply reauthorizes both the mutation permission and current entity access.

## Task definitions

Start with two bounded tasks:

- `rewrite_dialogue`: one proposal following explicit direction;
- `dialogue_variants`: at most three proposals with length/output caps.

Tasks preserve placeholders, technical ids, markup/schema constraints, and requested locale. Invalid variants are rejected rather than partially repaired silently.

## Proposal/apply contract

- Reusable `AiProposalPanel` displays variant, diff, warnings, provenance, and actions.
- Operation stores base text/revision hash and context hash.
- Apply reauthorizes `:edit_content`, obtains the existing collaboration lock/mutation path, and performs compare-and-set against the base revision.
- Changed source returns `:stale_proposal`; it never overwrites newer collaborator edits.
- Apply uses existing facades/versioning/undo and broadcasts through existing collaboration contracts.
- A valid variant set has `execution_status = succeeded`. Rejecting one variant is an item event, not the operation's terminal disposition. Applying one sets `user_disposition = accepted`; dismiss-all sets `user_disposition = dismissed`; expiry without a choice sets `user_disposition = abandoned`.

## Command palette and surface

- Contextual `Rewrite selected dialogue…` and `Generate dialogue variants…` commands use palette v2 `launch`; the proposal surface collects direction/locale/route choice and confirms cost before creating an operation.
- Availability requires the correct editor/selection, flag, permission, current revision, task/lane availability, and an executable result destination.
- The palette may open from supported editable contexts; the current selection is captured before focus moves.
- Destination is the proposal panel, not the palette itself.

## Existing code to reuse

Flow dialogue/response forms and mutation facades · collaboration locks/broadcasts · versioning/undo · Slice-2 operations/palette v2 · Slices 3–5 routing · Slice-6 context builder · shared diff/panel/dialog components · analytics/i18n.

## Non-goals

- Multi-node rewriting or automatic flow edits.
- Continuous autocomplete.
- Unbounded style chat.
- Automatic application or silent stale merge.
- Voice generation (Slice 9).

## Observability and error handling

- Record operation status, variant count, lane/provider/model, context size, and item/product outcomes without dialogue content.
- Provider/schema/placeholder/length/stale/lock errors are distinct localized states.
- Regenerate is a deliberate new operation and cost, disclosed before execution.

## Verification / Definition of Done

- ExUnit: task/context caps, locale and placeholder preservation, schema rejection, permission, lock + revision guard, apply through facade, undo/broadcast, operation/item outcome semantics.
- Vitest: proposal diff, per-variant selection, apply/dismiss/regenerate, stale state, managed price vs BYOK disclosure.
- Browser: two collaborators prove a proposal cannot overwrite a line changed after generation.
- Palette command works from the dialogue editor and captures the correct selection.
- User docs cover provider/cost, privacy, proposals, and stale behavior.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/ai-dialogue-tools` from `main` → PR → merge before slices reusing proposal UX. Flag: `:ai_integrations`.

## Inputs from previous slices

Slices 2–6; Slice 1 palette; existing flow collaboration/versioning.
