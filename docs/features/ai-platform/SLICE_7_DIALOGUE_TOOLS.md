# Slice 7 — Dialogue Tools (rewrite/variants + proposal UX)

## Objective

"Propose N variants of this dialogue line" and "Rewrite with direction X" on a selected dialogue node — generation grounded in the speaking character's sheet and the node's incoming conditions/variables, delivered through a **proposal → accept/reject UX** that doubles as the acceptance-telemetry instrument (the north-star metric).

## Problem & proposed solution

**Problem:** first _generative mutation_ of project data. Direct AI writes would bypass collaboration locks, undo, and authorization — and without an accept/reject affordance we cannot measure whether AI output is actually used.
**Solution:** AI never writes directly. `AI.execute(:dialogue_variants)` returns candidates; a proposal panel shows them as diffs against the current text; **Apply** routes through the existing node-update path (undo-able, authorized, broadcast to collaborators); every apply/dismiss is recorded as an acceptance event tied to the usage row. **Lock caveat: verify at implementation start whether the shared node-update path enforces lock ownership server-side; if enforcement is client-side only, this slice adds the server-side ownership check + conflict response BEFORE reusing the path for AI applies** — "locks respected" must be a tested property, not an assumption.

## Architectural direction

- Task defs: `:dialogue_variants` (standard tier, fixed credit price, bounded output). Context via Slice 5: dialogue node + speaker sheet (relevant blocks) + incoming condition/variable summary — NOT the whole flow.
- Proposal UX as a reusable pattern (`AiProposalPanel.vue` + a small proposal-state composable): variant list, per-variant diff vs current, Apply / Dismiss / Regenerate. Designed for reuse by Slice 8 (structure diffs) — build minimal, but with that consumer in mind.
- Apply = the SAME `pushEvent` the manual editor uses for dialogue text updates (`NodeUpdate` handlers) — zero new mutation paths. Optimistic UI per project policy (field edits reflect pre-round-trip).
- Acceptance telemetry: `ai_usage_events` row gets a follow-up acceptance record (accepted variant index | dismissed) — schema addition agreed in Slice 2's metering design.
- Entry points: palette command (dialogue node selected) + node context menu (existing flow context-menu plugin).

## Existing code to reuse (do not duplicate)

Dialogue per-type node module + `NodeCrud`/`NodeUpdate` handlers · `Collaboration.Locks` + `broadcast_change` · **flow-editor history: the Rete `HistoryPlugin`/`NodeDataAction` path (the flow editor does NOT use `StoryarnWeb.Helpers.UndoRedoStack` for node edits — Apply and undo tests must exercise the actual Rete history)** · flow context-menu plugin (shipped) · rete↔Vue reactivity contract (`nodeDataVersion`, `reactiveNodeData`) · `ConfirmDialog.vue` (destructive dismiss-all only if needed) · Slice-1 palette · Slice-2 execute/credits · Slice-5 context builder · `Authorize.with_edit_authorization` for apply events.

## Applicable conventions (MUST be surfaced in chat during implementation)

Every mutating `handle_event` authorized (apply = `:edit_content`) · collaboration: lock check before apply, broadcast after · optimistic UI for the applied text · no rich-text marks in dialogue V2 (project decision — plain text pipeline) · Vue: emits, stable `v-for` keys (variant index is NOT stable across regenerate — use generated ids) · i18n en/es for all proposal UI · icons Lucide · component registry check before `AiProposalPanel` (verify nothing equivalent exists — surface findings in chat).

## Observability & error handling

Acceptance events (apply/dismiss per variant) are the north-star telemetry · generation failure = explicit panel error with user-initiated regenerate (no auto-retry) · apply conflict (collaboration lock held) = explicit conflict state naming the holder — the apply NEVER proceeds against a lock and never retries silently · charged-but-failed generations are visible in the usage event trail (succeeded=false) · user docs: dialogue tools + proposal flow documented in the flag-hidden AI docs.

## Verification / Definition of Done

- ExUnit: task def + charging, context scoping for the node, apply path reuses NodeUpdate (assert broadcast + undo entry), acceptance events recorded for apply AND dismiss.
- Vitest: proposal panel states (loading, variants, error, applied), regenerate flow, emit contracts.
- Browser: full loop on a real dialogue node in a two-session collab scenario (lock respected); undo restores pre-apply text; credits debited; acceptance telemetry visible.
- `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-dialogue-tools` from main → PR → merge before Slice 8 (which reuses the proposal UX). Flag: `:ai_integrations` (the single AI flag; the palette itself is unflagged).

## Inputs from previous slices

Slices 1, 2, 5, 6 merged (6 provides the panel/acceptance precedent — reflected in the OVERVIEW dependency table). Estimate: **8–12h**.
