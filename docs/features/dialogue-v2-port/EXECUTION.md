# Dialogue V2 Port — Execution Plan

**Companion to:** [`REFACTOR.md`](./REFACTOR.md). Read REFACTOR.md first — it captures the audit + diff matrix + decision log. This doc lays out the phased delivery.

**Branch:** `feat/live-vue-sheets`. No new branch.

**Methodology:** vertical slices. Every phase ends in a user-testable outcome reachable in the browser. No phase leaves the codebase compiling-but-broken.

**Pre-release policy:** fresh migrations, no backcompat shims, rename freely (per `project_no_consumers_fresh_migrations_ok.md`).

**V1 reference worktree:** `/tmp/storyarn-main`. Already open. Keep it through Phase 6 — the diff matrix in REFACTOR.md is exhaustive but implementation may need to spot-check V1 visuals.

---

## Phase summary

| # | Title | Outcome (user-testable) | Estimate |
|---|---|---|---|
| 1 | Wire-format fix | Response editing actually works end-to-end (add / remove / edit text / condition / instruction). | 2-3h |
| 2 | Editor parity (audio + localization + generate-id + word-count footer) | Screenplay editor reaches V1 field-level parity. | 3-4h |
| 3 | PropsSerializer + camelCase + inline-edit HTML preservation | DialogueNode + panel use camelCase props end-to-end. Inline-edit no longer destroys formatting. | 3-4h |
| 4 | Visual port + god-component split + dead-code cleanup | DialogueNode and DialogueToolbar match V1 visually using shadcn primitives. No hand-rolled CSS forks. Dead fallbacks removed. | 4-6h |
| 5 | i18n key sweep + mobile fullscreen panel + edge polish | All V1 strings ported. Panel goes fullscreen on mobile (xl breakpoint match). | 2-3h |
| 6 | Collab broadcast for dialogue panel + test sweep | Two tabs editing the same dialogue stay in sync. 30+ Vitest tests pass. Backend regression suite green. | 3-4h |

**Total:** 17-24h. Variable because phases 4 + 6 can balloon if visual polish is taken to production-grade.

**Reporting cadence:** after each phase, ship the commit, browser-verify the listed outcomes, and report. Do NOT chain phases without verification.

---

## Phase dependencies

- **F1 unblocks F2-F6.** No editing makes sense if responses can't be saved.
- **F3 (PropsSerializer) is required before F4** because F4 splits DialogueNode into sub-components and they need a typed payload, not raw `node.data`.
- **F2 is independent of F3/F4** — could theoretically run in parallel, but a single agent should serialise to keep test discipline.
- **F5 mostly independent** — could run after F2.
- **F6 last** because it depends on the final wire shape.

---

## Phase 1 — Wire-format fix

Detail: [`phase-1-wire-format.md`](./phase-1-wire-format.md).

**Outcome:** the user can open a dialogue node, click "Add response" → response appears, type text → saves, set condition → saves, set instruction assignments → saves, delete response → gone, all without LV process crashes.

**Scope:**
- Fix `FlowScreenplayEditor.vue` push-event payloads to match V1 wire contract from REFACTOR.md §4 (key spelling, missing keys, value types).
- Stringify `condition` before push.
- Rename `update_response_assignments` → `update_response_instruction_builder`.
- Route screenplay-editor `update_node_text` through the existing `update_node_text` handler (already correct on V2; verify).
- Add Vitest tests for every push event payload — one test per event + a "smoke" test that mounts the editor and walks add → edit → delete.

**Verification:**
- Browser: open flow with at least 1 dialogue, open screenplay panel, exercise add/remove/text/condition/instruction. Watch server logs for `FunctionClauseError` (must be zero).
- Backend tests: `mix test test/storyarn_web/live/flow_live/nodes/dialogue_node_test.exs` (43+ tests, all green).
- Vitest: 5+ new tests under `assets/app/test/modules/flows/components/FlowScreenplayEditor.test.ts`.

**Decisions invoked:** D1, D3 from REFACTOR.md §10.

---

## Phase 2 — Editor field parity

**Outcome:** the screenplay editor's Settings tab has audio picker, localization id field with copy button, generate-technical-id button, and the footer shows word count + audio-attached label. Visually matches V1's Settings tab (modulo daisyUI → shadcn).

**Scope:**

1. Extract a new shared component `DialogueAudioPicker.vue` inside `assets/app/modules/flows/components/dialogue/` (new dir to host all dialogue-specific Vue components):
   - Wraps `AssetPicker` with audio kind, optional preview controls (matching `AudioAsset.vue` pattern from `FlowSequenceConfigPanel`).
   - Props: `assetId`, `audioAssets`, `canEdit`, `label`.
   - Emits: `select`, `clear`.
   - Follows the camelCase + global-component-no-domain-coupling rule (per `feedback_global_components_no_domain_coupling.md`). If it ends up dialogue-specific, keep it under `modules/flows/components/dialogue/`. If it's reusable, move to `assets/app/components/assets/`.
2. Add `LocalizationField.vue` (input + copy button). Reusable across future entities.
3. Add the "Generate technical ID" refresh button next to the technical-id input. Pushes `generate_technical_id` event.
4. Footer: word count (using `dngettext` plural — Vue uses `vue-i18n` plural format), "Audio attached" label.
5. `node.ex` already has `handle_generate_technical_id/1` — verify wiring; no backend change.
6. Backend: confirm `:audio_picker` PubSub is no longer needed by the V2 path. If it still has callers from sheets/scenes, leave it. If not, remove (out of scope but flag for cleanup).

**Vitest:**
- `DialogueAudioPicker.test.ts`: select / clear emits, prop pass-through.
- `LocalizationField.test.ts`: copy button visibility, copy event.
- `FlowScreenplayEditor.test.ts`: word-count plural rendering, generate-technical-id push event.

**Verification:**
- Browser: open dialogue, attach audio → reload → still attached. Click generate-technical-id → input updates with `<flow_shortcut>_<speaker>_<count>`. Copy localization-id → clipboard contains correct string.

**Decisions invoked:** D2.

---

## Phase 3 — PropsSerializer + camelCase + inline-edit HTML

**Outcome:** all dialogue panel props are camelCase. Backend ships a structured payload via `PropsSerializer.dialogue_panel_data/2`. Canvas inline-edit no longer destroys HTML formatting.

**Scope:**

1. Backend: introduce `StoryarnWeb.FlowLive.Helpers.PropsSerializer` (new file or co-locate in `generic_node_handlers.ex` if there's already a precedent — the audit says sequence builds it inline in `generic_node_handlers.ex` as `defp build_sequence_panel_data`). Make a public `dialogue_panel_data/2` returning the camelCase shape from REFACTOR.md §5.
2. Frontend: rewrite `FlowScreenplayEditor.vue` props interface in camelCase. Read from a single `data` prop returned by the serializer.
3. Frontend: rewrite `DialogueNode.vue` props interface in camelCase. The canvas still receives raw `node.data`, but the *prop* interface declared inside `DialogueNode.vue` translates at the boundary (a small adapter at the top of `<script setup>` that maps incoming snake_case `data` → typed camelCase locals).
4. Frontend: rewrite `DialogueToolbar.vue` props in camelCase.
5. Inline-edit fix (D7 from REFACTOR.md §10): clicking the dialogue text in canvas edit-mode opens the screenplay panel and focuses the TipTap editor. Remove the local `<textarea>` for text. Keep stage_directions and menu_text inline editors (they're plain strings — no HTML round-trip risk).

**Vitest:**
- `DialogueNode.test.ts`: snake_case→camelCase adapter, `previewText`, edit-mode entry triggers panel open.
- `FlowScreenplayEditor.test.ts`: receives `data` prop, renders correct fields.

**Verification:**
- Browser: open dialogue with rich-text body (bold, italic) → canvas preview shows correct text → click into edit-mode → panel opens with TipTap focused → edit + close → canvas updates. No formatting loss.

**Decisions invoked:** D5, D7.

---

## Phase 4 — Visual port + component split + cleanup

**Outcome:** DialogueNode and DialogueToolbar match V1 visually. Hand-rolled `<style>` block in DialogueNode replaced with shadcn primitives. DialogueAudioPreview uses Lucide instead of the 🔊 emoji. Dead code paths removed.

**Scope:**

1. Replace `DialogueNode.vue` inline `<input>`/`<textarea>` with shadcn `Input` / `Textarea`. Drop the scoped `<style>` block.
2. Split `DialogueNode.vue` into:
   - `DialogueNode.vue` (orchestrator, ~100 lines).
   - `DialogueNodeHeader.vue` (speaker + audio indicator).
   - `DialogueNodeBody.vue` (visual strip + preview / inline edit).
   - `DialogueNodeSockets.vue` (responses + badges + sockets row).
3. `DialogueToolbar.vue`: replace `Settings` icon with `BookOpen` for screenplay button (V1 used `settings`; V2's choice is open — pick `BookOpen` for clarity, log as decision D9 if course-corrected).
4. `DialogueAudioPreview.vue`: replace 🔊 emoji with Lucide `Volume2`.
5. Remove `DialogueToolbar.vue:60` `location_sheet_id` fallback (D8).
6. Collapse `:editor` editing mode into `:screenplay` (D4). Audit `show.ex` for any other `:editor` references first.
7. `FlowNode.vue:70`: remove default fallback to DialogueNode for unknown types. Add a placeholder `UnknownNode.vue` instead (D6).
8. Visual diff against V1: open a dialogue in V2, screenshot, open same flow in V1 worktree (start a separate Phoenix server on port 4001 if needed), screenshot, side-by-side compare. Iterate.

**Vitest:**
- One Vitest per new component (Header, Body, Sockets) with prop pass-through + visual structure assertions.
- `DialogueAudioPreview.test.ts`: renders Volume2 when assetId set, nothing otherwise.

**Verification:**
- Browser: dialogue node renders identically to V1 main reference (avatar strip, badges, sockets layout, header gradient). Inline-edit-mode shows shadcn Input styling.
- Visual regression: at least one screenshot pair preserved in a session note (not committed; ephemeral verification artefact).

**Decisions invoked:** D4, D6, D8.

---

## Phase 5 — i18n + mobile + edge polish

**Outcome:** every V1 Gettext key the dialogue uses has a corresponding V2 i18n key in `assets/app/locales/en/flows.json` (and `es/`). Panel goes fullscreen on mobile under `xl` breakpoint, mirroring V1's `inset-0 z-[1030] bg-base-100`. Plurals work.

**Scope:**

1. Compare V1 keys (REFACTOR.md §6.D) against V2 `flows.json`. Add missing.
2. `FlowScreenplayEditor.vue` mobile layout: outer container becomes `inset-0 z-[1030] bg-background xl:inset-auto xl:right-3 xl:top-[76px] xl:bottom-3 xl:w-[600px]`. Mobile header with arrow-left + title + X. Tabs stay sticky at top.
3. Word-count plural via `vue-i18n`'s `tc` (or `$t` with count): `flows.screenplay_editor.word_count` with plural form.
4. Verify `vue-i18n` setup exposes plurals correctly in `setup.ts` test environment.
5. Edge: keyboard Esc closes panel (V1 has it via JS hook; V2 should add a `useKeyboard` Esc binding scoped to the panel).
6. Edge: details `phx-hook="DetailsPreserveOpen"` analogue: ensure the response Advanced collapsibles preserve open state across re-renders. (Vue + LiveVue should handle this naturally if `open` is in component state, not derived from server props.)

**Vitest:**
- i18n completeness test: load every key referenced in dialogue Vue components, assert `flows.json` has them.
- Plural rendering: 0 / 1 / 5 word renderings.
- Esc key closes panel.

**Verification:**
- Browser: shrink viewport below 1280px → panel goes fullscreen with mobile header. Press Esc → closes. Open response Advanced → click outside → reopen → still expanded.

---

## Phase 6 — Collab broadcast + test sweep + regression

**Outcome:** two tabs editing the same dialogue stay in sync (panel data refreshes when the other user edits). Final sweep: `mix test`, `mix precommit`, `npm test`, all green. 30+ Vitest tests covering dialogue components.

**Scope:**

1. Add `broadcast_change` calls to dialogue handlers analogous to F6 sequence collab:
   - `update_node_field` already broadcasts via `persist_node_update`'s `:node_updated` — but the panel's `data` assign isn't refreshed for the receiver unless the receiver has the panel open on this node.
   - Add receiver clauses in `collaboration_event_handlers.ex`: `:dialogue_panel_refresh` when `editing_mode == :screenplay && selected_node.id == sequence_id`. Mirror `refresh_sequence_panel_if_open/2`.
2. Backend test sweep: `mix test test/storyarn_web/live/flow_live/`. Triage failures.
3. Vitest sweep: `npm test`. Triage failures.
4. Manual multi-tab verification: open dialogue panel in two tabs, edit text in tab A → tab B reflects after blur.

**Decisions invoked:** none new.

---

## Decisions ledger

Tracked in REFACTOR.md §10. Course-correctable up to one phase later.

| ID | Decision | Phase invoked |
|---|---|---|
| D1 | All screenplay-editor edits route through `persist_node_update` | 1 |
| D2 | `:audio_picker` PubSub replaced by `update_node_field` | 2 |
| D3 | `condition` always serialised to string at wire | 1 |
| D4 | `:editor` editing mode collapsed into `:screenplay` | 4 |
| D5 | `PropsSerializer.dialogue_panel_data/2` introduced | 3 |
| D6 | `FlowNode.vue:70` default fallback to DialogueNode removed | 4 |
| D7 | Inline-edit on canvas opens panel instead of forking TipTap | 3 |
| D8 | `DialogueToolbar.vue:60` `location_sheet_id` fallback removed | 4 |
| D9 (tentative) | `Settings` → `BookOpen` icon for screenplay toolbar button | 4 |

---

## Cross-session handoff

A fresh session picking up this work should:

1. Read `REFACTOR.md` for context (audit + diffs + decisions).
2. Read this file for phase status.
3. Check the memory pointer `project_dialogue_v2_port_status.md` for shipped-vs-pending.
4. Open the V1 worktree if not present: `git worktree add /tmp/storyarn-main main`.
5. Start the next pending phase. Verify outcome before moving on.

---

## Appendix — agent prompts used for the audit

For reproducibility. The two-agent split avoided cross-bias.

### V1 audit agent (Opus, Explore subagent)

- Worktree: `/tmp/storyarn-main`.
- Scope: backend + frontend + tests + i18n + migrations.
- Output: 10-section markdown report, ≤ 3000 words.
- Forbidden: reading current cwd; modifying anything.

### V2 audit agent (Opus, Explore subagent)

- Cwd: branch `feat/live-vue-sheets`.
- Scope: same axes as V1, plus a "why this is terriblemente mal montado" section.
- Output: 10-section markdown report, ≤ 3000 words.
- Forbidden: reading `/tmp/storyarn-main`; modifying anything.

Synthesis: this doc set + the diff matrix in REFACTOR.md §6.
