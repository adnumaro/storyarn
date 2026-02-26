# Stress Test Issues — Planescape: Torment

**Date:** 2026-02-23
**Test data:** Planescape: Torment characters, stats, quests, flow, and scene
**Compile status:** PASS (`mix compile --warnings-as-errors` clean)
**Last reviewed:** 2026-02-24

## Summary

| #   | Severity | Area    | Issue                                                  | Status             |
|-----|----------|---------|--------------------------------------------------------|--------------------|
| 1   | Minor    | Sheets  | Table block label not editable inline                  | Open               |
| 2   | Major    | Sheets  | KeyError crash in undo/redo snapshot (row.shortcut)    | **Open — confirmed** |
| 3   | Minor    | Sheets  | "Add column" button unresponsive to mouse clicks       | Open               |
| 4   | Moderate | Flows   | Drag-to-connect nodes is unreliable on canvas          | Open               |
| 5   | Minor    | Scenes  | Pin placement blocked by zone click targets            | Open               |
| 6   | Major    | Flows   | GenServer crash: node_moved fires after node deletion  | **Open — confirmed** |
| 7   | Moderate | Flows   | "+ Add response" creates hidden first response         | Open               |
| 8   | Minor    | Assets  | No multi-file upload — must upload one file at a time  | Open               |
| 9   | Minor    | Sheets  | Divider block has no label field — cannot name sections | Open               |

**2 major bugs** (Issue #2 — undo crash; Issue #6 — GenServer crash on move after delete)
**2 moderate UX issues** (Issue #4 — drag-to-connect unreliable; Issue #7 — hidden first response)
**5 minor UX issues** (Issues #1, #3, #5, #8, #9)

---

## Issue #1: Table block label not editable inline

- **Severity:** minor / UX friction
- **Status:** Open — no inline editing added yet
- **Context:** Creating a table block on "Main Characters" sheet. Tried to rename the default "Label" text by clicking and double-clicking on it.
- **Problem:** Clicking or double-clicking on the table block label ("Label") only toggles the collapsed/expanded state. There is no inline editing affordance. To rename the block, you must: click the "..." menu > select "Config" > edit the name in the sidebar panel.
- **Expected:** Double-clicking on the block label should allow inline editing (consistent with how sheet titles work — triple-click to select, type to replace).
- **Proposal:** Add inline edit on double-click for block labels. The sidebar config should remain as an alternative path, but the most common action (renaming) should be directly accessible.

## Issue #2: KeyError crash in undo/redo snapshot when adding table row

- **Severity:** major / bug
- **Status:** **Open — confirmed still present** (`undo_redo_handlers.ex:811` still reads `row.shortcut` but `TableRow` schema has `slug`)
- **Context:** Adding rows to the "Stats" table on "Main Characters" sheet. The 4th row ("Row 4") triggered a GenServer crash.
- **Problem:** `StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers.table_row_to_snapshot/1` (line 811) accesses `row.shortcut`, but the `Storyarn.Sheets.TableRow` schema has a `slug` field, not `shortcut`. This causes a `KeyError` every time a table row is added and the undo/redo system tries to snapshot it.
- **Stack trace:** `undo_redo_handlers.ex:811 → table_handlers.ex:159 → handle_add_row/3`
- **Root cause:** `lib/storyarn_web/live/sheet_live/handlers/undo_redo_handlers.ex:811` — `shortcut: row.shortcut` should be `slug: row.slug`.
- **Impact:** The row IS created in the database (the operation succeeds), but the undo/redo history is corrupted — the user cannot undo the row creation. The LiveView process crashes and recovers, but undo state is lost.
- **Fix:** Change line 811 from `shortcut: row.shortcut` to `slug: row.slug`. Also audit all other `*_to_snapshot` functions in the same file for similar field name mismatches.

## Issue #3: "Add column" button on table blocks unresponsive to mouse clicks

- **Severity:** minor / UX friction (possible browser-specific)
- **Status:** Open — needs runtime verification
- **Context:** Game State sheet, Quest Flags table. After creating the table and configuring the first column, tried clicking the "+" button on the right edge to add a new column.
- **Problem:** The "+" add-column button (`phx-click="add_table_column"`) does not respond to visual mouse clicks. Multiple attempts at clicking the button (both via coordinates and via accessibility ref) failed silently. The button only triggered successfully via a JavaScript `.click()` call.
- **Possible causes:** (1) The button may be partially obscured by a neighboring element or have zero visual hit area; (2) The button appears in a hover-only strip that may lose hover state before click registers; (3) Possible z-index stacking issue with the table border/container.
- **Workaround:** The button does exist in the DOM with `phx-click="add_table_column"` and works when triggered programmatically.
- **Proposal:** Investigate the add-column button's click target area. Consider making it wider or ensuring it has a stable hit area even after table interactions.

## Issue #4: Flow canvas — dragging to connect nodes is unreliable

- **Severity:** moderate / UX friction
- **Status:** Open — needs runtime verification
- **Context:** Flow "Morte - Mortuary Intro" on Rete.js canvas. Attempted to connect Entry → Dialogue, Dialogue response → Condition, and Condition → Exit by dragging from output port circles to input port circles.
- **Problem:** Drag-to-connect between node ports is extremely unreliable. Out of ~8 manual drag attempts, only 2 succeeded. The others either: (a) moved the target node instead of creating a connection, (b) failed silently with no visual feedback, or (c) started a connection line that didn't attach.
- **Possible causes:** (1) Port circles (~8-10px) have very small hit areas making them hard to grab; (2) Mouse-down on the port may be registering on the node body instead, initiating a move; (3) There may be a z-index issue where the node body intercepts events before the port.
- **Workaround:** Connections can be created programmatically via the Rete.js editor API: `hook.editor.addConnection({source, sourceOutput, target, targetInput})`.
- **Impact:** Core workflow action (connecting nodes) requires many retries. Users may become frustrated when basic node connections fail repeatedly.
- **Proposal:** Increase port hit area (e.g., invisible 20px circle around the visual 8px port). Consider adding a right-click > "Connect to..." context menu as an alternative connection method. Also investigate whether the node drag handler is stealing mousedown events from ports.

## Issue #5: Scene editor — pin placement blocked by zone click targets

- **Severity:** minor / UX friction
- **Status:** Open — needs runtime verification
- **Context:** Scene "Mortuary 1st Floor". After adding zones (Preparation Room, Embalming Room), used the pin tool with "From Sheet" to place character pins.
- **Problem:** When in pin placement mode ("Click on canvas to place X"), clicking on or near a zone selects the zone instead of placing the pin. The pin placement mode stays active but the click is consumed by the zone's click handler.
- **Expected:** While in pin placement mode, clicking anywhere on the canvas (including on zones) should place the pin. Zone selection should be suppressed during pin placement.
- **Workaround:** Click on empty canvas areas far from any zone to place pins.
- **Proposal:** When the scene editor is in pin placement mode, suppress zone/element selection and prioritize the placement action for all canvas clicks.

## Issue #6: GenServer crash — `node_moved` event fires for already-deleted node

- **Severity:** major / bug (GenServer crash, LiveView process terminates)
- **Status:** **Open — confirmed still present on both JS and Elixir sides**
  - JS: Neither `keyboard_handler.js:115` nor `context_menu_items.js:275` cancel `debounceTimers[nodeId]` before pushing `delete_node`.
  - Elixir: `generic_node_handlers.ex:349` still uses `get_node!` (raising variant).
- **Context:** Flow editor, deleting nodes after moving them. The user drags a node (which queues a debounced `node_moved` event), then deletes the node before the debounce fires.
- **Problem:** The JS-side `debounceNodeMoved` function (`assets/js/flow_canvas/handlers/editor_handlers.js:36-48`) uses a 300ms debounce timer before pushing a `node_moved` event to the server. When a node is deleted (via Delete key at `keyboard_handler.js:115` or context menu at `context_menu_items.js:275`), neither code path cancels the pending debounce timer for that node. The timer fires after the node is already soft-deleted (`deleted_at` set), and the server-side handler at `generic_node_handlers.ex:349` calls `Flows.get_node!/2` which uses `Repo.one!/1` — this raises `Ecto.NoResultsError` because the query filters `is_nil(deleted_at)`.
- **Stack trace:**
  ```
  (ecto) Ecto.Repo.Queryable.one!/3
  (storyarn) generic_node_handlers.ex:349: handle_node_moved/2
  (phoenix_live_view) Phoenix.LiveView.Channel.view_handle_event/3
  ```
- **Root cause (JS — primary):** `debounceNodeMoved` stores timers in `hook.debounceTimers[nodeId]` but neither the keyboard delete handler nor the context menu delete handler clears `hook.debounceTimers[nodeId]` before pushing `delete_node`. The 300ms timer outlives the node.
- **Root cause (Elixir — secondary):** `handle_node_moved/2` uses the raising variant `get_node!/2` instead of the non-raising `get_node/2`. A `node_moved` event for a recently-deleted node is a benign race condition that should be silently ignored, not crash the process.
- **Impact:** The LiveView GenServer crashes and the user's session is interrupted. Phoenix recovers the process, but any unsaved client-side state (selection, scroll position, undo history) is lost.
- **Fix options (both should be applied):**
  1. **JS fix:** Cancel pending debounce timer when deleting a node. In both delete paths, add:
     ```javascript
     if (hook.debounceTimers[nodeId]) {
       clearTimeout(hook.debounceTimers[nodeId]);
       delete hook.debounceTimers[nodeId];
     }
     ```
  2. **Elixir fix:** In `handle_node_moved/2`, replace `get_node!` with `get_node` (non-raising) and return `{:noreply, socket}` if the node is `nil`. This makes the server resilient to any remaining race conditions (e.g., collaborative delete by another user).
- **Relevant files:**
  - `assets/js/flow_canvas/handlers/editor_handlers.js:36-48` — debounce timer
  - `assets/js/flow_canvas/handlers/keyboard_handler.js:111-118` — keyboard delete (no timer cancel)
  - `assets/js/flow_canvas/context_menu_items.js:271-276` — context menu delete (no timer cancel)
  - `assets/js/flow_canvas/history_preset.js:106,122` — undo/redo delete (no timer cancel)
  - `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex:348-363` — server handler using `get_node!`
  - `lib/storyarn/flows/node_crud.ex:46-52` — `get_node!` query with `is_nil(deleted_at)` filter

## Issue #7: "+ Add response" button creates hidden first response on first click

- **Severity:** moderate / UX friction
- **Status:** Open — needs runtime verification (rendering code looks correct, may have been fixed by per-type node architecture refactor)
- **Context:** Flow editor, screenplay editor (fullscreen dialogue editor). When editing any dialogue node (States 2, 4, 5, 6, 7, etc.), clicking the "+ Add response" button to add the first response to a node.
- **Problem:** The first click on "+ Add response" creates a response in the data model but does NOT render it visually. The response panel remains empty — no input field appears. Only a subtle dark bar/spacer appears above the "+ Add response" button, hinting something was created. A second click on "+ Add response" then renders BOTH responses at once (showing "Responses 2" with Response 1 and Response 2 fields).
- **Reproduction steps:**
  1. Open the screenplay editor for a dialogue node with 0 responses
  2. Click "+ Add response" once
  3. Observe: No response input field appears. The "Responses" tab still shows no count or shows a blank area.
  4. Click "+ Add response" a second time
  5. Observe: Two response fields now appear ("Response 1" and "Response 2"), with count showing "Responses 2"
- **Consistency:** Reproduced on every single dialogue node created during the stress test (10+ nodes). The bug is 100% consistent.
- **Impact:** Users creating dialogue nodes with a single response must always: (1) click twice to make responses visible, (2) delete the unwanted extra response. This doubles the interaction cost for the most common case (single-response dialogue). For nodes needing 2 responses, the double-click accidentally creates the right number, masking the bug.
- **Expected:** The first click on "+ Add response" should immediately render one visible response input field with focus set to it.
- **Likely root cause:** The server-side handler for `add_response` correctly appends a response to the node's data, but the LiveView diff/patch for the first response may not trigger a re-render of the response list component. Possible causes: (1) The responses list component conditionally renders only when `length(responses) > 1`; (2) A `phx-update` or stream issue where the first item insertion doesn't trigger the container to appear; (3) The response list container starts hidden/collapsed and only expands when it detects multiple items. The canvas node uses `dialogue.js:needsRebuild` which does a full JSON stringify comparison — so the canvas node should rebuild. The issue likely lives in the sidebar/screenplay editor HEEx rendering path.
- **Workaround:** Always click "+ Add response" twice, then delete the extra response via the trash icon.
- **Relevant files (investigation starting points):**
  - `lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex` — `handle_add_response` handler
  - `lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex` — Response list rendering
  - `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` — Fullscreen editor response panel

---

## Issue #8: No multi-file upload in Assets — must upload one file at a time

- **Severity:** minor / quality of life
- **Status:** Open
- **Phase:** Phase 0 — Pre-Production
- **Context:** Uploading 8 asset files (character art, maps) to the Assets library for the stress test project.
- **Problem:** The Upload button only accepts a single file at a time. The hidden `<input id="asset-upload-input">` has no `multiple` attribute. To upload 8 files, the user must click Upload, select a file, wait for it to finish, then repeat 7 more times.
- **Expected:** The upload input should accept multiple files (`multiple` attribute) so users can select several files at once and have them uploaded in batch. This is standard behavior in asset management tools.
- **Proposal:** Add the `multiple` attribute to the file input and modify the `AssetUpload` hook to loop over `e.target.files` instead of only reading `files[0]`. Process uploads sequentially (to avoid overwhelming the server) with a progress indicator showing "Uploading 3/8...".
- **Relevant files:**
  - `assets/js/hooks/asset_upload.js:10` — reads only `files[0]`
  - `lib/storyarn_web/live/asset_live/index.ex` — upload handler

---

## Issue #9: Divider block has no label field — cannot name sections

- **Severity:** minor / missing feature
- **Status:** Open
- **Phase:** Phase 1 — The Awakening
- **Context:** Adding a Divider block on "Main Characters" sheet to create an "Attributes" section header. Selected scope "This sheet and all children", then added the Divider block type.
- **Problem:** The Divider block renders as a thin horizontal line only. There is no label/title text visible on the block. Opening the "Configure Block" panel shows only "Type: divider" and a "Required" toggle — no Label or Name field. There is no way to give the divider a section title like "Attributes" or "Alignment".
- **Expected:** Dividers should act as section headers with an editable label. The block picker should create a divider with a default label (e.g., "Label" or "Section"), and the Configure panel should include a "Label" text input. The label should render as text next to or above the divider line.
- **Impact:** Without labels, dividers are purely visual separators. Users cannot create named sections to organize blocks into logical groups (e.g., "Attributes", "Class & Progression", "Notes"). This significantly reduces the organizational value of divider blocks.
- **Proposal:** Add a `label` field to the Divider block's Configure panel and render it inline with the divider line (e.g., left-aligned text with a line extending to the right, similar to HTML `<fieldset>` legends).
- **Relevant files:**
  - `lib/storyarn_web/components/block_components/layout_blocks.ex` — divider rendering
  - `lib/storyarn_web/live/sheet_live/show.ex` — block config panel

---

## What Worked Well

Features that functioned correctly during the stress test:

### Sheets & Blocks
- Project creation with workspace assignment
- Sheet hierarchy (parent-child: Characters > Main Characters > The Nameless One, Morte)
- All block types tested: number, text, select, boolean, divider
- Table blocks: creation, row addition (despite undo crash), column addition (via JS), cell editing
- Property inheritance: parent sheet blocks inherited by child sheets
- Block override: child sheets can override inherited values
- Sheet shortcuts generated correctly (`#characters`, `#main-characters`, `#the-nameless-one`, `#morte`)
- "Own blocks" section for child-specific fields

### Flows
- Flow creation and naming
- Node creation: Entry, Exit, Dialogue, Condition (all via right-click context menu)
- Dialogue editor: speaker assignment, rich text editing, word count display
- Response creation (+ Add response button)
- Response text editing inline
- Auto-layout (repositions all nodes neatly)
- Canvas zoom and pan

### Scenes
- Scene creation with shortcut generation
- Zone creation (Rectangle shape tool)
- Zone naming via floating toolbar
- Pin placement from sheets ("From Sheet" → select sheet → click canvas)
- Layer sidebar (Default layer)
- Scene toolbar with all tools (cursor, pan, zone, pin, annotation, connection, freeform)
