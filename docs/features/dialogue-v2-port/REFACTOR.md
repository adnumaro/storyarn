# Dialogue Node — V1→V2 Port Refactor (audit + spec)

**Status:** Spec locked 2026-04-26. Implementation pending across 6 phases (see [`EXECUTION.md`](./EXECUTION.md)).

**Why this exists:** the V2 dialogue node is broken. Per the user, _"el dialogue está terriblemente mal montado"_. The Vue surface diverges from the V1 (HEEx + DaisyUI) reference at the wire level, the visual level, and the pattern level. This doc captures (1) the V1 reference behaviour we must reach, (2) the V2 current state, (3) the diff matrix that drives the phasing.

**Scope contract:** 1:1 port of V1 behaviour onto the V2 stack (Vue 3 + shadcn-vue + Tailwind + LiveVue). No design or product decisions — anything that diverges is a bug to fix. Future-feature surface is captured in §11 and is **explicitly out of scope** for this port.

**Stack reference:**

- V1 (`main`): HEEx + DaisyUI + TailwindCSS + plain LiveView + Lit web components for canvas nodes. Read-only worktree at `/tmp/storyarn-main` while this port is active.
- V2 (`feat/live-vue-sheets`): Vue 3 (script setup, lang="ts") + shadcn-vue + TailwindCSS v4 + LiveVue bridge + rete-vue-plugin canvas.

---

## 1. File inventory

### V1 (`/tmp/storyarn-main`)

Backend:

- `lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex` — type module + dialogue handlers (`handle_add_response`, `handle_remove_response`, `handle_update_response_text`, `handle_update_response_condition`, `handle_update_response_instruction`, `handle_update_response_instruction_builder`, `handle_generate_technical_id`, `handle_open_screenplay`).
- `lib/storyarn_web/live/flow_live/show.ex` — host LiveView; routes events to `Dialogue.Node`.
- `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` — generic `update_node_field`, `update_node_text`, `update_node_data`.
- `lib/storyarn_web/live/flow_live/handlers/editor_info_handlers.ex` — `{:node_updated, node}` proxy from screenplay editor.
- `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` — HEEx LiveComponent: Text / Responses / Settings tabs, mobile fullscreen + desktop floating.
- `lib/storyarn_web/live/flow_live/components/flow_toolbar.ex` — `render_toolbar("dialogue", ...)` floating toolbar.
- `lib/storyarn_web/live/flow_live/helpers/node_helpers.ex` — `persist_node_update/3`, `canvas_data/2` (type-warning enrichment).
- `lib/storyarn_web/live/flow_live/helpers/form_helpers.ex` — `node_data_to_form/1`, `sheets_map/2`.
- `lib/storyarn_web/components/audio_picker.ex` — LiveComponent inside Settings tab.
- `lib/storyarn/flows.ex` — `serialize_for_canvas/2` (lines 658-705 in main), `instruction_sanitize/1`.
- `lib/storyarn/flows/instruction.ex` — `sanitize/1` for response `instruction_assignments`; `has_type_warnings?/2`.
- `lib/storyarn/flows/evaluator/node_evaluators/dialogue_evaluator.ex` — runtime evaluator.
- `lib/storyarn/screenplays/{node_mapping,reverse_node_mapping,flow_sync,auto_detect}.ex` — bidirectional sync.
- `lib/storyarn/references/*` — entity + variable reference tracking.
- `lib/storyarn/localization/*` — localized text extraction.

Frontend (Lit + JS hooks):

- `assets/js/flow_canvas/nodes/dialogue.js` — Lit canvas renderer (view + renderEdit).
- `assets/js/flow_canvas/nodes/render_helpers.js` — shell, header, sockets.
- `assets/js/flow_canvas/components/storyarn_node.js` — Lit host element.
- `assets/js/flow_canvas/event_bindings.js` — `node-inline-edit`, `speaker-select-open`, push events.
- `assets/js/hooks/dialogue_screenplay_editor.js` — Phoenix hook on the editor panel.
- `assets/js/hooks/tiptap_editor.js` + `assets/js/tiptap/*` — TipTap editor for dialogue body.
- `assets/js/utils/searchable_dropdown.js` — speaker combobox.
- `assets/js/hooks/details_preserve_open.js` — keeps response Advanced `<details>` open across re-renders.

Tests:

- `test/storyarn_web/live/flow_live/nodes/dialogue_node_test.exs` (442 lines).
- `test/storyarn_web/live/flow_live/components/screenplay_editor_test.exs` (1423 lines).
- `test/storyarn/flows/evaluator/dialogue_evaluator_test.exs` (299 lines).
- `test/storyarn/screenplays/{node_mapping,reverse_node_mapping,flow_sync}_test.exs`.
- No JS tests for dialogue.

### V2 (current branch)

Backend:

- `lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex` — same per-type module structure as V1. Handlers identical.
- `lib/storyarn_web/live/flow_live/handlers/preview_handlers.ex` — runtime preview state machine + serializer.
- `lib/storyarn_web/live/flow_live/show.ex` — V2 wires events to Vue components.
- `lib/storyarn_web/live/flow_live/helpers/node_helpers.ex` — `persist_node_update`, type-warning enrichment for `dialogue` (lines 312-327).
- `lib/storyarn/flows.ex` — `serialize_for_canvas` + `maybe_add_type_warning_flag` for dialogue.
- `lib/storyarn/flows/entity_trash_refs.ex` — soft-delete sweep for `speaker_sheet_id`.

Frontend (Vue):

- `assets/app/modules/flows/nodes/DialogueNode.vue` (389 lines) — canvas node body.
- `assets/app/modules/flows/nodes/DialogueAudioPreview.vue` — speaker-icon badge.
- `assets/app/modules/flows/components/toolbar-sections/DialogueToolbar.vue` (107 lines) — floating toolbar.
- `assets/app/modules/flows/components/FlowScreenplayEditor.vue` (336 lines) — right-side editor panel.
- `assets/app/modules/flows/components/FlowPreview.vue` — runtime preview dialog.
- `assets/app/modules/flows/components/dock-panels/DockNarrativePanel.vue` — bottom-dock add entry.
- `assets/app/modules/flows/lib/node-configs.ts` — pin metadata, `createDynamicOutputs`, `dialogueNeedsRebuild`.
- `assets/app/modules/flows/types.ts` — `DialogueResponse`, `SheetMapEntry`, `SheetAvatarEntry`.
- `assets/app/modules/flows/lib/render-helpers.ts` — `previewText`, `stripHtml`.
- `assets/app/modules/flows/components/{FlowFloatingToolbar,FlowNodeToolbar}.vue` — host toolbar dispatch.

Tests:

- Backend: `test/storyarn_web/live/flow_live/nodes/dialogue_node_test.exs` (handler-level coverage). No `screenplay_editor_test.exs` analogue exists for the Vue panel.
- Frontend: **zero**. No tests for `DialogueNode.vue`, `FlowScreenplayEditor.vue`, `DialogueToolbar.vue`, `DialogueAudioPreview.vue`.

---

## 2. Schema + data model

`flow_nodes.data` JSONB. Same shape across V1 and V2 (data layer untouched by the port).

| Field              | Default             | Type                               | V1 surface                                                                      | V2 surface                                                   |
| ------------------ | ------------------- | ---------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `speaker_sheet_id` | `nil`               | `int \| nil` (id of a sheet)       | EntityCombobox in canvas + screenplay editor + sync                             | Same                                                         |
| `text`             | `""`                | TipTap HTML `<p>...</p>`           | TipTap in panel; `update_node_text` on inline-edit (server wraps plain → `<p>`) | TipTap in panel; **inline-edit destroys HTML (bug)**         |
| `stage_directions` | `""`                | plain string                       | inline + panel `Input`                                                          | inline + panel `Input`                                       |
| `menu_text`        | `""`                | plain string                       | inline + panel `Input` (Settings tab)                                           | inline + panel `Input` (Settings tab)                        |
| `audio_asset_id`   | `nil`               | `int \| nil`                       | Settings tab `AudioPicker` LiveComponent                                        | **No picker — read-only icon only (bug)**                    |
| `technical_id`     | `""`                | string                             | toolbar input + Settings input + `generate_technical_id` button                 | toolbar input + Settings input. **No generate button (bug)** |
| `localization_id`  | `"dialogue.<6hex>"` | string                             | Settings input + copy-to-clipboard                                              | **No UI at all (bug)**                                       |
| `avatar_id`        | `nil`               | int referencing `sheet_avatars.id` | toolbar `avatar_picker` popover                                                 | toolbar `ToolbarAvatarPicker`. **No editor surface (gap)**   |
| `responses`        | `[]`                | list of maps (see below)           | sockets + Responses tab                                                         | sockets + Responses tab (broken at wire)                     |

Response shape:

```elixir
%{
  "id" => "r1_<unique_int>",
  "text" => "Response 1",
  "condition" => nil | string | map,    # see §3
  "instruction" => nil | string,         # legacy plain text, no V1/V2 UI
  "instruction_assignments" => [...]     # structured builder; see Storyarn.Flows.Instruction
}
```

Computed/transient fields (added in serializer; not persisted):

- `responses[].has_type_warnings` — set by `Flows.serialize_for_canvas` when an assignment's value type mismatches the variable type.
- `responses[].linked_screenplay_id` — set by `NodeMapping.map_responses/1` and used by `FlowSync` to track child screenplay pages.
- `dual_dialogue` — written by Fountain dual-dialogue importer; **never rendered in any UI** (V1 quirk preserved verbatim).
- `has_stale_refs`, `unreachable`, `dead_end` — set by serializer.

`condition` polymorphism: tests assert it can be a string (`"health > 50"`) OR a map (`%{"logic" => "all", "rules" => [...]}`) OR nil. The dialogue evaluator's runtime guard expects a binary string. The V2 `FlowScreenplayEditor` types it as `ConditionData` object — type contract mismatch (bug, see §9).

`location_sheet_id` — legacy import-only field. Read by `DialogueToolbar.vue:60` as avatar fallback. Has no editor in either V1 or V2; remains in `data` only via parsers / versioning. The V2 toolbar's read of it is dead-data path that should be removed.

---

## 3. CRUD + lifecycle

Single canonical write path: `NodeHelpers.persist_node_update/3`.

1. Reads fresh from DB.
2. Applies caller transform.
3. `Flows.update_node_data` runs in a transaction:
   - `WordCount.for_node_data("dialogue", data)` → writes `word_count`.
   - `References.update_flow_node_entity_references` → re-extracts sheet refs from `text`, `menu_text`, `stage_directions`, response texts.
   - `References.update_flow_node_variable_references` → extracts `$ref` variable usages.
   - `Localization.extract_flow_node` → syncs localization-key-indexed strings.
4. Reloads flow, broadcasts `:node_updated`, pushes `node_updated` to canvas, emits `node_data_changed` (undo snapshot), runs `mark_saved` + `schedule(:flow)`.

V1 quirk preserved verbatim: the V1 `ScreenplayEditor` LiveComponent has its own write path that bypasses `persist_node_update` and writes via `Flows.update_node_data` directly + `send/2` to the parent. Result: edits made through the screenplay panel **skip the undo snapshot and the per-edit broadcast**. V2 inherits this asymmetry implicitly via `update_node_field` events that DO go through `persist_node_update`. Decision: V2 should route ALL screenplay-editor edits through `persist_node_update` (canonical path) — this is a port improvement that matches the V1 _intent_ even though it diverges from the V1 _implementation_. Recorded as Phase-1 decision §10.

Connection migration on response add/remove (preserved in both versions, `dialogue/node.ex:78-150`):

- Adding the FIRST response migrates the existing `output` connection to the new response id.
- Removing the LAST response migrates connections back from that response id to `"output"`.
- Removing a non-last response simply deletes outgoing connections from that pin.

Validation: there is no schema-level validation of the dialogue `data` shape. Type correctness lives at consumer sites only. **Out of scope for the port.** F3 of the relational refactor (see `docs/features/flow-relational-refactor/REFACTOR.md`) lifts dialogue into typed tables; this port stays on the JSONB model.

Duplicate cleanup (`Dialogue.Node.duplicate_data_cleanup/1`): clears `technical_id`, regenerates `localization_id`. Response IDs survive (they include `:erlang.unique_integer/1`, no collision). V1 + V2 identical.

---

## 4. LiveView events (wire contract — the source of truth)

All event names + params shapes the V2 port must satisfy. Backend handlers all live under `Dialogue.Node` or `GenericNodeHandlers`. Param keys are quoted strings (LiveView wire format).

### Speaker

| Event               | Params                                                      | Handler                                        | Notes                             |
| ------------------- | ----------------------------------------------------------- | ---------------------------------------------- | --------------------------------- |
| `update_node_field` | `%{"field" => "speaker_sheet_id", "value" => "<id>" \| ""}` | `GenericNodeHandlers.handle_update_node_field` | Empty string normalised to `nil`. |

### Text (dialogue body)

| Event              | Params                                          | Handler                                       |
| ------------------ | ----------------------------------------------- | --------------------------------------------- |
| `update_node_text` | `%{"id" => node_id, "content" => "<p>...</p>"}` | `GenericNodeHandlers.handle_update_node_text` |

V2 must emit HTML (TipTap output) on every update, NOT plain string. Inline canvas edit (if preserved as a feature) must wrap plain text in `<p>` with `<br>` for blank lines, mirroring V1's server-side wrap.

### Stage directions / menu text / technical_id

| Event               | Params                                                                                 | Handler |
| ------------------- | -------------------------------------------------------------------------------------- | ------- |
| `update_node_field` | `%{"field" => "stage_directions" \| "menu_text" \| "technical_id", "value" => string}` | generic |

### Generate technical_id

| Event                   | Params                       | Handler                                        |
| ----------------------- | ---------------------------- | ---------------------------------------------- |
| `generate_technical_id` | `%{}` (uses `selected_node`) | `Dialogue.Node.handle_generate_technical_id/1` |

### Localization id

| Event               | Params                                               | Handler |
| ------------------- | ---------------------------------------------------- | ------- |
| `update_node_field` | `%{"field" => "localization_id", "value" => string}` | generic |

### Audio

V1 wire: AudioPicker LiveComponent emits `select_audio` / `remove_audio` to itself, then `send(self(), {:audio_picker, :selected, asset_id})` to the parent. Parent `show.ex` calls `NodeHelpers.persist_node_update` to write `audio_asset_id`.

V2 port decision: **drop the `:audio_picker` PubSub and route through `update_node_field`** with `field: "audio_asset_id", value: <id>|nil`. Mirrors how `FlowSequenceConfigPanel.vue` writes `background_asset_id` via `update_sequence_config`. The PubSub layer is a V1 implementation artefact; the simpler path is what V2 already uses for sequences.

### Avatar

| Event               | Params                                                | Handler |
| ------------------- | ----------------------------------------------------- | ------- |
| `update_node_field` | `%{"field" => "avatar_id", "value" => "<id>" \| nil}` | generic |

### Responses

V1 wire (preserved verbatim — these are the contracts the backend handler `Dialogue.Node.handle_*_response` matches on):

| Event                                 | Params                                                                 | Handler                                                      |
| ------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------ |
| `add_response`                        | `%{"node-id" => node_id}`                                              | `Dialogue.Node.handle_add_response/2`                        |
| `remove_response`                     | `%{"response-id" => id, "node-id" => node_id}`                         | `Dialogue.Node.handle_remove_response/2`                     |
| `update_response_text`                | `%{"response-id" => id, "node-id" => node_id, "value" => text}`        | `Dialogue.Node.handle_update_response_text/2`                |
| `update_response_condition`           | `%{"response-id" => id, "node-id" => node_id, "value" => string}`      | `Dialogue.Node.handle_update_response_condition/2`           |
| `update_response_instruction`         | `%{"response-id" => id, "node-id" => node_id, "value" => string}`      | legacy; not wired in V2 UI either                            |
| `update_response_instruction_builder` | `%{"response-id" => id, "node-id" => node_id, "assignments" => [...]}` | `Dialogue.Node.handle_update_response_instruction_builder/2` |
| `update_response_condition_builder`   | builder-specific (routes to `Condition.Node`)                          | `update_response_condition_builder`                          |

The V2 `FlowScreenplayEditor.vue` currently uses `response_id` (underscore) and `text` (instead of `value`) and omits `node-id` entirely. **Every response event is wire-broken.** Phase 1 of EXECUTION fixes this.

Condition encoding: v1 stores `condition` as a string (raw expression OR JSON-serialised object). The dialogue evaluator runtime guard `is_binary(condition_string)` requires a string. The V2 panel currently passes a `ConditionData` object — the wire must serialise to string before push. Decision: use `Flows.condition_to_json` server-side (already exists for the condition node) and on the V2 side stringify with `JSON.stringify(condition)` before pushing. **Phase 1.**

### Screenplay open / close

| Event             | Params                                   | Handler                                   |
| ----------------- | ---------------------------------------- | ----------------------------------------- |
| `open_screenplay` | `%{"id" => node_id}` (optional fallback) | `Dialogue.Node.handle_open_screenplay/2`  |
| `close_editor`    | `%{}`                                    | `GenericNodeHandlers.handle_close_editor` |
| `deselect_node`   | `%{}`                                    | generic                                   |

V1 has both `:screenplay` and `:editor` editing modes mapping to the same panel (`screenplay_editor.ex`). V2 inherits both in `show.ex:235`. Decision: collapse to a single mode `:screenplay` — `:editor` is a V1 leftover never assigned anywhere in the dialogue path. **Phase 4.**

### Misc

| Event                       | Params                 | Handler                                     |
| --------------------------- | ---------------------- | ------------------------------------------- |
| `mention_suggestions`       | `%{"query" => string}` | `EditorInfoHandlers` (proxied to Vue panel) |
| `variable_suggestions`      | `%{"query" => string}` | `EditorInfoHandlers`                        |
| `resolve_variable_defaults` | `%{"refs" => [...]}`   | `EditorInfoHandlers`                        |
| `start_preview`             | `%{"id" => node_id}`   | `PreviewHandlers.handle_start_preview`      |

---

## 5. Serializer

V1 and V2 use the same `Flows.serialize_for_canvas/2` plus `NodeHelpers.canvas_data/2` for single-node updates. `data` flows through verbatim with these added fields:

- `responses[].has_type_warnings` (set per response).
- `has_stale_refs`, `unreachable`, `dead_end` (full-flow only — not on single-node updates).

There is **no snake_case → camelCase conversion** for dialogue. This breaks V2's documented rule that all Vue props must be camelCase (memory: `feedback_camelcase_props.md`). Sheet/Scene have a `PropsSerializer` helper; flows do not.

V2 port decision: introduce `StoryarnWeb.FlowLive.Helpers.PropsSerializer.dialogue_panel_data/2` mirroring the per-panel serializer pattern from `generic_node_handlers.ex::build_sequence_panel_data/2`. The serializer:

1. Takes `socket` + `node` (must be `type: "dialogue"`).
2. Returns a camelCase, structured payload `%{nodeId, speakerSheetId, text, stageDirections, menuText, technicalId, localizationId, audioAssetId, avatarId, responses: [%{id, text, condition, hasTypeWarnings, ...}], allSheets, projectVariables, ...}`.
3. Replaces the current pattern of feeding raw `node.data` + ad-hoc `allSheets`/`projectVariables` props.

The canvas path (`DialogueNode.vue`) keeps reading raw `data` for now — refactoring the canvas serializer is F3 territory and out of scope. Only the panel adopts the PropsSerializer pattern. **Phase 3.**

---

## 6. UI inventory + the diff matrix

### V1 reference UI (the visual port spec)

#### A. Canvas node body (`assets/js/flow_canvas/nodes/dialogue.js` in main)

Two render modes: `render` (view) and `renderEdit` (inline-edit).

View mode:

- Wrapper `nodeShell(color, selected, ..., "dialogue min-w-[280px] max-w-[350px]")`. Border-color = sheet color or `#3b82f6`.
- Header: `px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]` with gradient using sheet color. Speaker icon (Lucide `MessageSquare` or sheet color block), speaker name OR "Dialogue", audio indicator (Lucide `volume-2`).
- Visual strip: avatar override (big `<img class="block w-[calc(100%-24px)] max-h-[200px] object-contain rounded-lg mx-3 mt-3">`); else sheet default avatar (`size-16 rounded-lg object-cover shadow-md` centered in tinted block); else empty tinted block; else nothing.
- Body `px-3.5 pt-2.5 pb-3`:
  - stage_directions: `italic text-base-content/55 text-xs mb-1 break-words`.
  - menu_text: `text-xs text-primary/70 font-medium mb-1 break-words` prefixed with `"≡ "`.
  - preview text (HTML stripped to text via DOMParser preserving newlines between block tags): `text-sm text-base-content/85 leading-relaxed break-words whitespace-pre-wrap`.
- Sockets footer: `py-1.5 border-t border-base-content/10`. Single response → inline single-row layout. Multi-response → per-response rows with output label + badges + circular socket on the right.

Per-response output badges:

- error pill (red filled circle, alert SVG), title = "Empty response text" if no text, "Type mismatch in assignments" if `has_type_warnings`.
- yellow `#eab308` dot tooltip "Has condition" if condition truthy.
- pink `#ec4899` dot tooltip "Has instructions" if `instruction_assignments.length > 0`.

Edit mode replaces:

- Header speaker name with a `inline-speaker-trigger` button (chevron) that fires DOM event `speaker-select-open` → `searchableDropdown` → push `update_node_field`.
- Body inputs (`@blur`-saved): inline-input for `stage_directions` (italic, border-b), inline-input for `menu_text` (`text-primary/70 font-medium`), inline-textarea for `text` (auto-grow). All `bg-transparent border-0`.

Output topology (`createOutputs`): if responses exist, return their IDs; else `null` (rete falls back to `["output"]`).

`needsRebuild` fires for: `speaker_sheet_id`, `audio_asset_id`, `avatar_id`, `has_stale_refs`, response count, response IDs, response `has_type_warnings`, response condition truthiness, response `instruction_assignments.length > 0`. NOT on text changes — preserves inline-edit optimistic state.

LOD: V1 dialogue does NOT branch on LOD. Same chrome at all zoom levels. **V2 must match.**

#### B. Floating toolbar (V1 `flow_toolbar.ex:56-117`)

Wraps in `flex items-center gap-1.5 text-sm`:

- Node-type icon (Lucide `MessageSquare`).
- Toolbar separator.
- Edit form (`phx-change="update_node_data"` debounce 500ms): technical_id `<input class="toolbar-input font-mono text-xs">`. Read-only mode shows `text-xs font-mono truncate max-w-[100px]`.
- Audio indicator (Lucide `volume-2 size-3.5 text-info`) if `audio_asset_id` truthy.
- Avatar picker (only when `can_edit && speaker_avatars != []`). Trigger button `toolbar-btn text-xs` (`text-primary` if override set). Popover: 3-column grid of avatar thumbs (`aspect-square rounded-md overflow-hidden border ...`), plus "Use default" button if override set.
- Settings button `phx-click="open_screenplay"` `class="toolbar-btn text-xs"`, Lucide `settings` icon, title "Open screenplay editor".
- Preview button `phx-click="start_preview"` with Lucide `play` icon.

#### C. Screenplay editor sidebar (V1 `screenplay_editor.ex`)

Outer container (`#dialogue-screenplay-editor`, `phx-hook="DialogueScreenplayEditor"`):

- Mobile: `inset-0 z-[1030] bg-base-100`.
- Desktop xl: `xl:inset-auto xl:right-3 xl:top-[76px] xl:bottom-3 xl:w-[600px]`.

Mobile header (`navbar bg-base-100 border-b border-base-300 px-4 shrink-0 xl:hidden`): arrow-left + "Back to canvas" + close X.

Desktop header (`hidden xl:flex items-center gap-2 px-3 py-2 border-b border-base-300`): node-type icon (opacity 60), speaker name `text-sm font-medium truncate flex-1`, X.

Tabs (`tabs tabs-bordered shrink-0 px-4 pt-2`): "Text", "Responses" (with `badge badge-xs badge-ghost ml-1` showing count when > 0), "Settings". Each `phx-click="switch_tab"`.

Footer (`border-t border-base-300 px-4 py-2 flex items-center justify-between text-xs text-base-content/50 shrink-0`):

- Left: speaker name (icon `user`), word count (icon `file-text`, `dngettext("flows", "%{count} word", "%{count} words", n)`), "Audio attached" string when `audio_asset_id` set.
- Right: `<span class="kbd kbd-xs">Esc</span> {dgettext "to close"}`.

##### Text tab

- Speaker selector (when `can_edit`): button `id="screenplay-speaker-btn" class="dialogue-sp-select-btn"` with `data-speakers` JSON, fed to `createSearchableDropdown` by hook. Pushes `update_speaker`. Hidden `<form phx-change="update_speaker">` for headless tests.
- Stage directions: `<input type="text" id="screenplay-stage-directions" name="stage_directions" class="dialogue-sp-input" placeholder="(stage directions)">` inside `<.form phx-change="update_stage_directions" phx-debounce="500">`.
- Dialogue text: TipTap editor (`phx-hook="TiptapEditor"`, `phx-update="ignore"`, `data-mode="dialogue-screenplay"`, `data-variables-enabled="true"`, `min-h-[200px] focus:outline-none`).
- Read-only branch: speaker as `<span class="sp-character-content">`, stage_directions in literal parens, dialogue editor renders with `data-editable="false"`.

##### Responses tab (`space-y-3 p-4`)

For each response:

- Card: `border border-base-300 rounded-lg p-3`.
- Row: `flex items-start gap-2` with arrow icon, `<textarea phx-blur="update_response_text" phx-value-response-id phx-value-node-id rows="2" class="textarea textarea-sm textarea-bordered w-full resize-none">`, delete button `class="btn btn-ghost btn-xs btn-square text-error"` with `trash-2`.
- Advanced `<details>` (`id="response-advanced-{id}"` `phx-hook="DetailsPreserveOpen"` `class="mt-2"`, `open` if `response_has_advanced?`). Summary with chevron + `bg-warning` dot if advanced set + "Advanced".
  - Inner `mt-2 space-y-2 pl-6`:
    - Condition: `<.expression_editor mode="condition" context={%{"response-id", "node-id"}} ...>`.
    - Instruction: `<.expression_editor mode="instruction" event_name="update_response_instruction_builder" context={%{"response-id", "node-id"}} ...>`.

Below: `<button phx-click="add_response" class="btn btn-ghost btn-sm gap-1 w-full">` + plus icon + "Add response".

##### Settings tab (`space-y-4 p-4`)

- Menu Text: label + form (`update_menu_text` debounced 500ms) with `<input class="input input-sm input-bordered w-full" placeholder="Short text shown in menus...">`.
- Audio: label + `<.live_component module={AudioPicker} id="screenplay-audio-picker-{node.id}" asset_id can_edit project current_user>`.
- Technical ID: label + flex row with form input (font-mono) + refresh button `phx-click="generate_technical_id" class="btn btn-ghost btn-sm btn-square"` with `refresh-cw` icon.
- Localization ID: label + flex row with form input (font-mono) + copy button (only when value non-empty) using `data-copy-text` + `copy` icon.

#### D. i18n keys (Gettext domain `flows`)

V1 inventory (full):

- "Dialogue", "Character speech and player responses".
- Inline edit (data-labels): "Search...", "Dialogue" (no_speaker), "Stage directions...", "Menu text...", "Dialogue text...", "Select avatar", "Use default".
- ScreenplayEditor: "Back to canvas", "Text", "Responses", "Settings", "to close", "%{count} word"/"%{count} words" (plural), "DIALOGUE", "SELECT SPEAKER", "Search...", "(stage directions)", "Enter dialogue text...", "Response %{n}", "Response text… (use $ref for variables)", "(empty response)", "Advanced", "Condition", "Instruction", "Add response", "Menu Text", "Short text shown in menus...", "Audio", "Audio attached", "Technical ID", "Auto-generated or custom", "Generate technical ID", "Localization ID", "Localization key", "Copy to clipboard".
- AudioPicker (domain `sheets`): "No audio", "Upload audio", "Uploading...", "Preview:", "Remove", "Your browser does not support audio playback."
- Toolbar: "Open screenplay editor".

V2 must port these keys to `assets/app/locales/{en,es}/flows.json` (and `common.json` for shared asset/audio strings). The V2 already has `flows.nodes.dialogue.*`, `flows.dialogue_toolbar.*`, `flows.screenplay_editor.*`, `flows.preview.*`. Phase 5 audits and fills missing keys.

### V2 current state — diff matrix

Severity legend: 🔴 broken (functional bug), 🟠 missing (feature absent), 🟡 stylistic / debt, 🟢 OK.

| Item                                               | V1                                              | V2                                                              | Severity          | Phase                                               |
| -------------------------------------------------- | ----------------------------------------------- | --------------------------------------------------------------- | ----------------- | --------------------------------------------------- |
| `add_response` event wire                          | `%{"node-id" => id}`                            | sends no `node-id`                                              | 🔴                | 1                                                   |
| `remove_response` event wire                       | `%{"response-id", "node-id"}`                   | sends `response_id` underscore, no `node-id`                    | 🔴                | 1                                                   |
| `update_response_text` event wire                  | `%{"response-id", "node-id", "value"}`          | sends `response_id`, `text`, no `node-id`                       | 🔴                | 1                                                   |
| `update_response_condition` event wire             | `%{"response-id", "node-id", "value"}` (string) | sends object, missing `node-id`, wrong key names                | 🔴                | 1                                                   |
| `update_response_assignments` event                | does not exist                                  | called by V2 (orphan)                                           | 🔴                | 1 (rename to `update_response_instruction_builder`) |
| `update_response_instruction_builder` caller       | screenplay editor                               | absent                                                          | 🔴                | 1                                                   |
| Response condition type                            | string at wire                                  | typed as `ConditionData` object                                 | 🔴                | 1 (stringify before push)                           |
| Inline-edit text round-trip                        | preserves HTML (server wraps plain)             | strips HTML → plain string overwrite                            | 🔴                | 3                                                   |
| Camera/canvas snake_case props                     | n/a (HEEx is server-rendered)                   | `DialogueNode.vue` + `DialogueToolbar.vue` use snake_case props | 🟠                | 3                                                   |
| Audio picker in editor                             | Settings tab live_component                     | absent                                                          | 🟠                | 2                                                   |
| Avatar picker in editor                            | (toolbar only)                                  | (toolbar only)                                                  | 🟢                | —                                                   |
| `localization_id` UI                               | Settings tab + copy button                      | absent                                                          | 🟠                | 2                                                   |
| `generate_technical_id` button                     | Settings tab refresh button                     | handler exists, no UI caller                                    | 🟠                | 2                                                   |
| Word count footer                                  | `dngettext` plural                              | absent                                                          | 🟠                | 2                                                   |
| Mobile fullscreen panel                            | yes                                             | n/a (panel only desktop)                                        | 🟡                | 5                                                   |
| Per-panel serializer (`build_dialogue_panel_data`) | n/a                                             | absent (raw `node.data` flows through)                          | 🟠                | 3                                                   |
| `condition` polymorphism                           | string                                          | string OR object (broken)                                       | 🔴                | 1                                                   |
| Inline-edit raw `<input>`/`<textarea>`             | Lit raw inputs                                  | scoped CSS forks design system                                  | 🟡                | 4                                                   |
| `DialogueNode.vue` size                            | n/a                                             | 389 lines god component                                         | 🟡                | 4                                                   |
| `DialogueAudioPreview.vue`                         | renders Lucide volume-2                         | renders 🔊 emoji glyph                                          | 🟡                | 4                                                   |
| `Settings` icon for screenplay                     | Lucide `settings`                               | Lucide `Settings`                                               | 🟢                | —                                                   |
| Editor `:screenplay` vs `:editor` modes            | both alive but only `:screenplay` reachable     | both alive                                                      | 🟡                | 4                                                   |
| Collab broadcasts on dialogue panel                | partial (V1 has the same gap)                   | partial                                                         | 🟡                | 6                                                   |
| Collab receiver clauses for panel                  | n/a                                             | n/a                                                             | 🟠                | 6                                                   |
| `FlowNode.vue:70` default fallback to DialogueNode | n/a (Lit uses explicit map)                     | renders unknown types as dialogues silently                     | 🟡                | 4 (cleanup)                                         |
| `location_sheet_id` toolbar fallback               | not surfaced                                    | reads dead field                                                | 🟡                | 4 (cleanup)                                         |
| Screenplay sync wire (`mention_suggestions`, etc.) | works                                           | works (already proxied)                                         | 🟢                | —                                                   |
| Screenplay/auto-detect/import paths                | `Storyarn.Screenplays.*`                        | unchanged                                                       | 🟢                | —                                                   |
| Backend dialogue handlers                          | comprehensive                                   | preserved verbatim                                              | 🟢                | —                                                   |
| Backend tests                                      | 442+1423+299 lines                              | only 442 (handlers) — no editor analogue                        | 🟠                | 6                                                   |
| Frontend tests                                     | none                                            | none                                                            | 🔴 (per user req) | every phase + dedicated 6                           |

---

## 7. Screenplay sync

V1 and V2 share `Storyarn.Screenplays.{NodeMapping, ReverseNodeMapping, FlowSync, AutoDetect}`. **No backend changes needed for the port.** What V2 lacks is the live UI proxies that V1's screenplay-editor LiveComponent owns:

- `mention_suggestions` / `variable_suggestions` / `resolve_variable_defaults` proxies (currently routed via `EditorInfoHandlers` and partial in V2 — verify in Phase 5).

Two-way live sync (concurrent edits between two screenplay editors on the same dialogue) is **NOT a V1 capability** — the V1 screenplay editor only updates on selection / re-render. Therefore not in scope for the 1:1 port. Future phase if collab is wanted (out of port scope; see §11).

---

## 8. Tests

### Backend coverage to preserve

- `dialogue_node_test.exs` (V2 already has): metadata, default*data, extract_form_data, duplicate_data_cleanup, all `handle*\*` clauses. **Pass throughout the port.**
- `screenplay_editor_test.exs` (V1 has, V2 missing): renders three tabs, word-count plurals, speaker picker, audio indicator, response cards, advanced indicator, switch_tab default + transitions, settings field updates, read-only mode, edge data shapes. **Phase 6** writes a Vue + LiveVue equivalent: handler-level integration tests + Vitest component tests.
- `dialogue_evaluator_test.exs`: present in both. **Don't touch.**
- `node_mapping_test.exs` / `reverse_node_mapping_test.exs` / `flow_sync_test.exs`: present. **Don't touch.**

### Vitest coverage targets (the user's "fuertemente testado" requirement)

Per phase, add Vitest tests for the components touched:

- Phase 1: `FlowScreenplayEditor.vue` event-shape tests (every push event payload, exact key spelling). 5+ tests.
- Phase 2: `DialogueAudioPicker.vue` (new) + `DialogueAvatarPicker.vue` (extracted) + `LocalizationField.vue` (new) — 3-4 tests each.
- Phase 3: `DialogueNode.vue` (split) — props serializer tests, inline-edit HTML round-trip test, `previewText` test. 6-8 tests.
- Phase 4: shadcn primitive replacements — visual regression via snapshot or attribute assertions. 4-6 tests.
- Phase 5: i18n key coverage test (every Gettext key referenced by Vue is in `locales/en/flows.json`). 1 test asserting completeness.
- Phase 6: backend handler regression sweep + multi-tab collab manual + a final Vitest suite run.

Target: **30+ Vitest tests for dialogue components by end of port.**

---

## 9. V1 quirks preserved verbatim (not bugs to fix)

Documented so the port doesn't accidentally fix what V1 deliberately keeps:

1. **`response.instruction` legacy plain-text field.** V1 stores it but no UI writes to it. V2 inherits — handler exists, no caller. Keep both.
2. **`dual_dialogue` invisible field.** Fountain dual-dialogue importer writes it; nothing renders it. Keep.
3. **Action lines as speakerless dialogues.** Screenplay-sync writes `speaker_sheet_id: nil` for action lines. Keep.
4. **`technical_id` is unconstrained.** No uniqueness check. Generate button silently overwrites. Keep — adding validation is a feature, not a port.
5. **`open_screenplay` race fallback.** Comment in `node.ex:201-207` documents the race with `close_editor`. The handler reads `params["id"]` as fallback. Keep.
6. **AudioPicker prop name V1 quirk.** `screenplay_editor.ex:392-399` passes `asset_id={...}` though the docstring says `selected_asset_id`. V2 will not inherit this since the V2 audio picker is rebuilt to use `assetId` prop (camelCase) consistent with `AudioAsset.vue`. **Documented improvement, not a quirk preserved.**

---

## 10. Decisions made (no user input needed; auto-mode defaults)

These are listed verbatim so a future session knows what was decided unilaterally and can flag corrections:

- **D1 — All screenplay-editor edits route through `persist_node_update`.** V1 has two write paths (the screenplay editor bypasses `persist_node_update`). V2 should unify. Rationale: undo + collab broadcasts must fire for every edit. This is a port improvement that aligns V2 with V1's _intent_. No user-visible regression.
- **D2 — `:audio_picker` PubSub replaced by `update_node_field` for `audio_asset_id`.** Mirrors `FlowSequenceConfigPanel` pattern. Simpler, no LiveComponent dependency. No user-visible diff.
- **D3 — `condition` is always serialised to string at the wire.** Backend stores string; evaluator expects string; V2 panel must `JSON.stringify(conditionObject)` before push, parse back on receive. Matches V1.
- **D4 — `:editor` editing mode collapsed into `:screenplay`.** `:editor` is an unreachable V1 leftover for dialogue.
- **D5 — Per-panel serializer `PropsSerializer.dialogue_panel_data/2` introduced.** Mirrors `build_sequence_panel_data/2`. All Vue dialogue panel props become camelCase. Canvas serializer (`serialize_for_canvas`) stays snake_case for now (canvas-side refactor is F3 territory).
- **D6 — `FlowNode.vue:70` default fallback to `DialogueNode` removed.** Unknown types render an explicit `<UnknownNode>` placeholder instead. Unrelated to dialogue but caught during audit.
- **D7 — Inline-edit on canvas preserves HTML.** Edit-mode opens TipTap-lite (or stays read-only with a "click to edit in panel" affordance) instead of stripping to plain string. Decision: edit-mode shows the rendered HTML preview but the actual editor is the screenplay panel — clicking inline-edit area opens the panel + focuses the dialogue text input. This sidesteps re-implementing TipTap inside the rete node.
- **D8 — `location_sheet_id` toolbar fallback removed.** Dead-data path; `DialogueToolbar.vue:60` only resolves avatars from `speaker_sheet_id`.

If the user disagrees with any decision, they course-correct on the next message. The plan is structured so each decision is reversible at most one phase later.

---

## 11. Future feature surface — NON-BINDING

Out of port scope. Surfaced only because the user asked for the option. Categorise as ideation; do **not** plan against this in EXECUTION.md.

- Per-response audio (voice-line) preview button in the canvas + panel.
- Per-response menu_text override for dialogue → hub fan-outs.
- Live collab on the dialogue panel itself (mirrors the F6 sequence collab pattern). Becomes cheap once `dialogue_panel_data` serializer exists.
- Inline screenplay-sync "out of date" indicator on the canvas node (checksum-based).
- Per-response avatar override (emotion variants).
- Bulk technical_id regeneration.
- Soft schema validation on `responses` shape (catches malformed sync payloads).
- Voice-line waveform / lip-sync hint display.
- Localization preview toggle (swap `text` for resolved string of `localization_id`).

---

## 12. References

- This doc: `docs/features/dialogue-v2-port/REFACTOR.md`
- Phased plan: `docs/features/dialogue-v2-port/EXECUTION.md`
- Phase 1 detail: `docs/features/dialogue-v2-port/phase-1-wire-format.md`
- Sibling refactor (precedent for the per-panel serializer + collab pattern): `docs/features/flow-relational-refactor/`
- V1 worktree (read-only during port): `/tmp/storyarn-main`
- V2 audit raw outputs: not persisted (regenerable via the agent prompts in `docs/features/dialogue-v2-port/EXECUTION.md::Appendix`).
