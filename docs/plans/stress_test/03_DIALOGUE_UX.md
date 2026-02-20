# 03 -- Dialogue Node UX: Floating Toolbar + Full Editor

| Field         | Value                                                                                 |
|---------------|---------------------------------------------------------------------------------------|
| Gap Reference | Gap 4 from `COMPLEX_NARRATIVE_STRESS_TEST.md`                                         |
| Priority      | HIGH                                                                                  |
| Effort        | High                                                                                  |
| Dependencies  | None (can be built before Gap 1 or Gap 5; subtask 6 is forward-compatible with Gap 5) |
| Previous      | `02_CANVAS_PERFORMANCE.md`                                                            |
| Next          | [`04_EXPRESSION_SYSTEM.md`](./04_EXPRESSION_SYSTEM.md)                                |

---

## Context and Current State

### Editing modes

`show.ex` (line 717) initialises `@editing_mode` to `nil`. The three states are:

| Mode           | Trigger                                    | What renders                                 |
|----------------|--------------------------------------------|----------------------------------------------|
| `nil`          | Page load, `close_editor`, `deselect_node` | Canvas only, no panel                        |
| `:sidebar`     | `node_selected`, `open_sidebar`            | Right 320 px panel (`node_properties_panel`) |
| `:screenplay`  | Double-click dialogue, `open_screenplay`   | Fullscreen overlay (`ScreenplayEditor`)      |

Transitions are handled in `GenericNodeHandlers` (`handle_node_selected` sets `:sidebar`, `handle_node_double_clicked` reads `on_double_click/1` from the type module, `handle_close_editor` resets to `nil`) and in `Dialogue.Node.handle_open_screenplay/1`.

### Screenplay editor

`/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` -- LiveComponent, `fixed inset-0 z-50`. Sections: header (Open Sidebar + Close), paper (speaker select + stage directions + TiptapEditor), footer (word count). Responses are **read-only** with a "Edit responses in the sidebar panel" message. Hook: `DialogueScreenplayEditor`.

### Dialogue sidebar

`/lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex` -- function component. Sections: speaker select, stage directions textarea, TiptapEditor for text, responses list (each with text input + collapsible "Advanced" containing a `condition_builder` + plain `<input type="text">` for instruction), collapsible menu text, collapsible audio (AudioPicker LiveComponent), collapsible technical IDs. All packed into a 320 px-wide aside.

### Properties panel

`/lib/storyarn_web/live/flow_live/components/properties_panels.ex` -- `node_properties_panel/1`: `<aside class="w-80">` with header, delegated body via `NodeTypeRegistry.sidebar_module/1`, footer with:
- "Open Screenplay" button (dialogue only)
- "Preview from here" button (dialogue only)
- "Delete Node" button + `<.confirm_modal id="delete-node-confirm">` (all deletable types)

### Dialogue node.ex

`/lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex` -- `on_double_click/1` returns `:screenplay`. Handlers: `handle_add_response`, `handle_remove_response`, `handle_update_response_text`, `handle_update_response_condition`, `handle_update_response_instruction`, `handle_generate_technical_id`, `handle_open_screenplay`.

### Map floating toolbar (reference pattern)

- **JS:** `/assets/js/map_canvas/floating_toolbar.js` -- `createFloatingToolbar(hook)` returns `{show, hide, reposition, setDragging}`. Uses `requestAnimationFrame`, `getBoundingClientRect`, clamps to canvas bounds, flips below if too close to top.
- **Hook:** `/assets/js/hooks/floating_toolbar.js` -- `updated()` callback re-applies positioning after LiveView patches.
- **HEEx:** `/lib/storyarn_web/live/map_live/components/floating_toolbar.ex` -- per-type toolbars (zone, pin, connection, annotation). Each has inline controls (inputs, color pickers, dropdowns) and a "More" popover.

### Keyboard handler

`/assets/js/flow_canvas/handlers/keyboard_handler.js` -- Delete/Backspace already deletes selected node immediately without confirmation (lines 102-108). `Escape` deselects.

### Delete pattern

Sidebar footer has a "Delete Node" button that opens `<.confirm_modal id="delete-node-confirm">`. Keyboard shortcut bypasses this and deletes directly. The goal of this plan is to remove the confirmation modal entirely, making keyboard and UI behaviour consistent.

---

## Subtasks

### Subtask 1: Remove delete confirmation from all node types

**Description:** Remove the "Delete Node" button and `confirm_modal` from the properties panel footer. Keyboard Delete/Backspace already works without confirmation, and Undo (Ctrl+Z) can restore deleted nodes via the existing `DeleteNodeAction` + `restore_node` undo history. This makes the delete UX zero-friction and consistent.

**Files affected:**

| File                                                               | Change                                                                                       |
|--------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/components/properties_panels.ex` | Remove the "Delete Node" button, the `<.confirm_modal>`, and the `:if` guard for entry nodes |

**Implementation steps:**

1. Open `properties_panels.ex`.
2. In `node_properties_panel/1`, locate the footer `<div class="p-4 border-t ...">`.
3. Remove the entire delete button block:
   ```elixir
   <button :if={@can_edit && @node.type != "entry"} ... phx-click={show_modal("delete-node-confirm")}>
   ```
4. Remove the `<.confirm_modal :if={...} id="delete-node-confirm" .../>` block.
5. Remove the `<p :if={@node.type == "entry"} ...>` paragraph ("Entry nodes cannot be deleted").
6. Keep the "Open Screenplay" and "Preview from here" buttons for dialogue nodes.
7. If the footer becomes empty for non-dialogue types, remove the footer div entirely and add a thin bottom padding to the scrollable body instead. To keep it simple: always render the footer, but only with dialogue-specific buttons. For non-dialogue nodes the footer will just be an empty padded div acting as visual spacing.
8. Remove the `alias Phoenix.LiveView.JS` import if it is no longer used after removing `show_modal`.

**Test battery:**

| Test                                                     | Location                                                                              | What it verifies                                                                            |
|----------------------------------------------------------|---------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Delete via keyboard still works                          | `/test/storyarn_web/live/flow_live/show_events_test.exs`                              | Existing test: `"delete_node"` event with node id deletes the node                          |
| Undo restores deleted node                               | `/test/storyarn_web/live/flow_live/show_events_test.exs`                              | Existing test: `"restore_node"` event re-creates the node                                   |
| Properties panel renders without delete button           | New test in `/test/storyarn_web/live/flow_live/components/properties_panels_test.exs` | `render_component(node_properties_panel, ...)` does **not** contain `"delete-node-confirm"` |
| Entry node panel renders without "cannot delete" message | Same test file                                                                        | Panel for entry node does not contain "Entry nodes cannot be deleted"                       |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 2: Floating toolbar infrastructure -- JS positioning module for flow canvas

**Description:** Create a reusable JS positioning module that places an absolutely-positioned DOM element above a selected Rete.js node. This adapts the map floating toolbar pattern (`/assets/js/map_canvas/floating_toolbar.js`) from Leaflet coordinates to Rete.js/rete-area-plugin coordinates.

**Files affected:**

| File                                              | Change                                                                                                              |
|---------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| New: `/assets/js/flow_canvas/floating_toolbar.js` | Positioning module: `createFlowFloatingToolbar(hook)` returning `{show, hide, reposition, setDragging}`             |
| `/assets/js/hooks/flow_canvas.js`                 | Instantiate toolbar, call `show/hide` on selection, `reposition` on area translate/zoom, `setDragging` on node drag |
| `/assets/js/flow_canvas/event_bindings.js`        | Wire `area:translate`, `area:zoom` events to `reposition()`                                                         |

**Implementation steps:**

1. Create `/assets/js/flow_canvas/floating_toolbar.js`:
   - Export `createFlowFloatingToolbar(hook)`.
   - Internal state: `currentNodeId`, `isDragging`.
   - `show(nodeId)`: Store `currentNodeId`, call `requestAnimationFrame(() => position())`.
   - `hide()`: Clear `currentNodeId`, remove `toolbar-visible` class from toolbar element.
   - `reposition()`: If `currentNodeId` is set and not dragging, call `position()`.
   - `setDragging(bool)`: Hide during drag, reposition on release.
   - `position()`: Core logic:
     a. Get toolbar element by ID `"flow-floating-toolbar"`.
     b. Get the Rete.js node view from `hook.area.nodeViews.get(currentNodeId)`.
     c. Read the node view's element `getBoundingClientRect()` to get screen coordinates.
     d. Measure toolbar dimensions via `getBoundingClientRect()` (temporarily make visible if hidden).
     e. Place toolbar centered horizontally above the node, clamped within the canvas container bounds.
     f. If too close to top edge, flip below the node.
     g. Apply `style.left`, `style.top`, add `toolbar-visible` class.

2. In `flow_canvas.js` `initEditor()`:
   - After plugins are created, instantiate: `this.floatingToolbar = createFlowFloatingToolbar(this)`.
   - Store a reference on the DOM element for the FloatingToolbar hook: `this.el.__floatingToolbar = this.floatingToolbar`.

3. In `event_bindings.js`:
   - After existing `area:translate` and `area:zoom` handlers, call `hook.floatingToolbar?.reposition()`.
   - In existing node drag handlers, call `hook.floatingToolbar?.setDragging(true/false)`.

4. In `editorHandlers` (or wherever `node_selected` / `deselect_node` are handled on the JS side):
   - On selection: call `hook.floatingToolbar?.show(nodeId)`.
   - On deselection: call `hook.floatingToolbar?.hide()`.

**Test battery:**

| Test                                 | Location                                                                                | What it verifies                                                                            |
|--------------------------------------|-----------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Module exports correct API           | New: `/assets/js/__tests__/flow_canvas/floating_toolbar.test.js` (if using vitest/jest) | `createFlowFloatingToolbar` returns object with `show`, `hide`, `reposition`, `setDragging` |
| Toolbar hidden when no node selected | Manual / E2E                                                                            | Toolbar div does not have `toolbar-visible` class on load                                   |
| Toolbar appears on node selection    | Manual / E2E                                                                            | After clicking a node, toolbar div gains `toolbar-visible` and is positioned near the node  |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 3: Dialogue floating toolbar -- HEEx component and container

**Description:** Create the HEEx component for the dialogue floating toolbar and wire it into `show.ex`. The toolbar shows: speaker dropdown, audio indicator, response count badge, Edit button, and Preview button. For non-dialogue node types, the toolbar is either empty or shows a minimal set (just the node type label). This subtask starts with dialogue-only; other node types can be added later.

**Files affected:**

| File                                                                   | Change                                                                                                            |
|------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| New: `/lib/storyarn_web/live/flow_live/components/dialogue_toolbar.ex` | Floating toolbar HEEx component                                                                                   |
| `/lib/storyarn_web/live/flow_live/show.ex`                             | Add toolbar container div inside the canvas area, conditionally render content                                    |
| New: `/assets/js/hooks/flow_floating_toolbar.js`                       | LiveView hook that calls `reposition()` after LiveView patches (same pattern as map's `floating_toolbar.js` hook) |
| `/assets/js/hooks/index.js`                                            | Register the new hook                                                                                             |

**Implementation steps:**

1. Create `/lib/storyarn_web/live/flow_live/components/dialogue_toolbar.ex`:
   ```elixir
   defmodule StoryarnWeb.FlowLive.Components.DialogueToolbar do
     use Phoenix.Component
     use Gettext, backend: StoryarnWeb.Gettext
     import StoryarnWeb.Components.CoreComponents

     attr :node, :map, required: true
     attr :form, :map, required: true
     attr :can_edit, :boolean, default: false
     attr :all_sheets, :list, default: []

     def dialogue_toolbar(assigns) do
       # Build speaker options, count responses, check audio
       ...
     end
   end
   ```
   The toolbar renders as a `<div class="flex items-center gap-1">` with:
   - Speaker `<select>` (compact, `select-xs`) -- fires `update_node_data` with `speaker_sheet_id`.
   - Audio indicator: `<.icon name="volume-2" />` badge if `audio_asset_id` is set.
   - Response count: `<span class="badge badge-sm">3 responses</span>`.
   - Edit button: `<button phx-click="open_screenplay" class="btn btn-primary btn-xs">` with `<.icon name="pencil" />` and "Edit" label.
   - Preview button: `<button phx-click="start_preview" phx-value-id={@node.id} class="btn btn-ghost btn-xs">` with `<.icon name="play" />`.

2. In `show.ex` render, inside the `<div class="flex-1 relative bg-base-200">` (the canvas container), add a toolbar container div **after** the `#flow-canvas` div:
   ```elixir
   <div
     id="flow-floating-toolbar"
     phx-hook="FlowFloatingToolbar"
     class="floating-toolbar absolute z-30 pointer-events-none"
   >
     <div
       :if={@selected_node && @selected_node.type == "dialogue" && @editing_mode == :sidebar}
       id="flow-floating-toolbar-content"
       class="pointer-events-auto"
     >
       <.dialogue_toolbar
         node={@selected_node}
         form={@node_form}
         can_edit={@can_edit}
         all_sheets={@all_sheets}
       />
     </div>
   </div>
   ```

3. Create `/assets/js/hooks/flow_floating_toolbar.js`:
   ```javascript
   export const FlowFloatingToolbar = {
     updated() {
       const canvas = document.getElementById("flow-canvas");
       if (canvas && canvas.__floatingToolbar) {
         canvas.__floatingToolbar.reposition();
       }
     },
   };
   ```

4. Register the hook in `/assets/js/hooks/index.js`.

5. Add CSS for `floating-toolbar` in the flow editor stylesheet (reuse the same `.toolbar-visible` pattern from the map editor -- opacity transition, pointer-events toggle).

**Test battery:**

| Test                                 | Location                                                                      | What it verifies                                                      |
|--------------------------------------|-------------------------------------------------------------------------------|-----------------------------------------------------------------------|
| Component renders speaker select     | New: `/test/storyarn_web/live/flow_live/components/dialogue_toolbar_test.exs` | `render_component` output contains `<select` and speaker options      |
| Component renders response count     | Same file                                                                     | Output contains response count text                                   |
| Component renders Edit button        | Same file                                                                     | Output contains `phx-click="open_screenplay"`                         |
| Component renders Preview button     | Same file                                                                     | Output contains `phx-click="start_preview"`                           |
| Audio indicator shown when audio set | Same file                                                                     | When `audio_asset_id` is non-nil, output contains `volume-2` icon     |
| Audio indicator hidden when no audio | Same file                                                                     | When `audio_asset_id` is nil, output does not contain `volume-2` icon |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 4: Full editor layout -- evolve screenplay_editor.ex into two-column layout

**Description:** Transform the existing `ScreenplayEditor` LiveComponent from a single-column screenplay format into a two-column full editor. Left column: speaker selector + stage directions + TiptapEditor for text. Right column: placeholder "Responses" section (actual response editing wired in Subtask 5). Footer: audio indicator + word count + technical/localization IDs.

**Files affected:**

| File                                                               | Change                                                     |
|--------------------------------------------------------------------|------------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` | Major layout rework: two-column grid, footer consolidation |

**Implementation steps:**

1. Restructure the `render/1` function:
   - **Header:** Replace "Open Sidebar" with "Back to canvas" (fires `close_editor`). Add a "Settings" gear button (popover placeholder -- wired in Subtask 7). Keep close button.
   - **Body:** Use a `grid grid-cols-1 lg:grid-cols-2 gap-6` layout inside the scrollable area:
     - **Left column** (`<div class="space-y-4">`):
       - Speaker selector (reuse existing `<.form>` + `<select>`).
       - Stage directions input (reuse existing).
       - TiptapEditor for text (reuse existing, `min-h-[300px]`).
     - **Right column** (`<div class="space-y-4">`):
       - `<h3>` "Responses" heading.
       - Placeholder: `<p class="text-sm text-base-content/60">` "Response editing coming in next subtask."
       - This placeholder will be replaced in Subtask 5.
   - **Footer:** Consolidate into a single bar:
     - Left section: audio indicator (icon + filename if set, or "No audio" text), word count.
     - Right section: technical_id (read-only display), localization_id (read-only display), "Esc to close" hint.

2. Update `assign_derived/1` to also compute `audio_asset_name` (look up in `all_sheets` or just show the ID -- keep it simple for now, just display presence/absence).

3. Keep all existing event handlers (`update_speaker`, `update_stage_directions`, `update_node_text`, `mention_suggestions`) unchanged.

4. The `on_open_sidebar` prop is no longer needed (there is no "Open Sidebar" button). Remove it from the component assigns and the caller in `show.ex`. Replace with a simple close action.

5. Update `show.ex` to remove `on_open_sidebar={JS.push("open_sidebar")}` from the ScreenplayEditor invocation.

**Test battery:**

| Test                            | Location                                                                       | What it verifies                                                 |
|---------------------------------|--------------------------------------------------------------------------------|------------------------------------------------------------------|
| Two-column layout renders       | New: `/test/storyarn_web/live/flow_live/components/screenplay_editor_test.exs` | Rendered HTML contains `grid-cols-2` class                       |
| Speaker selector still works    | Same file                                                                      | Contains `<select` with speaker options                          |
| Stage directions input renders  | Same file                                                                      | Contains stage directions input with placeholder                 |
| TiptapEditor container renders  | Same file                                                                      | Contains `phx-hook="TiptapEditor"` element                       |
| Footer shows word count         | Same file                                                                      | Footer contains "word" text                                      |
| Footer shows audio status       | Same file                                                                      | Footer contains audio indicator when `audio_asset_id` is present |
| "Back to canvas" button present | Same file                                                                      | Contains close/back button                                       |
| No "Open Sidebar" button        | Same file                                                                      | Does **not** contain "Open Sidebar" text                         |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 5: Full editor response editing -- right column with response cards

**Description:** Replace the right column placeholder with full response editing. Each response renders as a card with: text input, remove button, and "Add response" button at the bottom. Wire existing response events (`add_response`, `remove_response`, `update_response_text`).

**Files affected:**

| File                                                               | Change                                                                                                     |
|--------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` | Replace right column placeholder with response card list; add response event handlers that proxy to parent |

**Implementation steps:**

1. In the right column of `render/1`, replace the placeholder with:
   ```elixir
   <div class="space-y-3">
     <div
       :for={{response, index} <- Enum.with_index(@form[:responses].value || [])}
       class="p-3 bg-base-200 rounded-lg space-y-2"
     >
       <div class="flex items-center gap-2">
         <span class="badge badge-sm badge-ghost">{index + 1}</span>
         <input
           type="text"
           value={response["text"]}
           phx-blur="update_response_text"
           phx-target={@myself}
           phx-value-response-id={response["id"]}
           phx-value-node-id={@node.id}
           placeholder={dgettext("flows", "Response text...")}
           disabled={!@can_edit}
           class="input input-sm input-bordered flex-1"
         />
         <button
           :if={@can_edit}
           type="button"
           phx-click="remove_response"
           phx-target={@myself}
           phx-value-response-id={response["id"]}
           phx-value-node-id={@node.id}
           class="btn btn-ghost btn-xs btn-square text-error"
         >
           <.icon name="x" class="size-3" />
         </button>
       </div>
       <!-- Condition + Instruction placeholders (Subtask 6) -->
     </div>
     <button
       :if={@can_edit}
       type="button"
       phx-click="add_response"
       phx-target={@myself}
       phx-value-node-id={@node.id}
       class="btn btn-ghost btn-sm gap-1 w-full border border-dashed border-base-300"
     >
       <.icon name="plus" class="size-4" />
       {dgettext("flows", "Add response")}
     </button>
   </div>
   ```

2. Add event handlers in the LiveComponent that proxy to the parent LiveView:
   ```elixir
   def handle_event("add_response", %{"node-id" => node_id}, socket) do
     send(self(), {:screenplay_event, "add_response", %{"node-id" => node_id}})
     {:noreply, socket}
   end

   def handle_event("remove_response", params, socket) do
     send(self(), {:screenplay_event, "remove_response", params})
     {:noreply, socket}
   end

   def handle_event("update_response_text", %{"response-id" => rid, "node-id" => nid, "value" => text}, socket) do
     send(self(), {:screenplay_event, "update_response_text", %{"response-id" => rid, "node-id" => nid, "value" => text}})
     {:noreply, socket}
   end
   ```

3. In `show.ex`, add a `handle_info` clause for `{:screenplay_event, event_name, params}` that delegates to the same handlers already used by the sidebar (e.g., `Dialogue.Node.handle_add_response`, etc.):
   ```elixir
   def handle_info({:screenplay_event, "add_response", params}, socket) do
     case authorize(socket, :edit_content) do
       :ok -> Dialogue.Node.handle_add_response(params, socket)
       {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
     end
   end
   ```

4. When the parent updates `@selected_node` after a response change, the LiveComponent receives the updated node via `update/2`, which calls `assign_derived/1` and refreshes the form. No extra wiring needed.

**Test battery:**

| Test                                 | Location                                                                  | What it verifies                                                                    |
|--------------------------------------|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| Response cards render                | `/test/storyarn_web/live/flow_live/components/screenplay_editor_test.exs` | Rendered HTML contains response text inputs                                         |
| Add response button present          | Same file                                                                 | Contains "Add response" button                                                      |
| Remove button present per response   | Same file                                                                 | Each response card has a remove button                                              |
| Add response event proxied to parent | Same file or integration test                                             | Sending `add_response` to the component triggers `{:screenplay_event, ...}` message |
| Response count updates after add     | Integration test                                                          | After adding a response, re-rendered component shows new response card              |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 6: Full editor response advanced features -- condition builder + instruction per response card

**Description:** Add condition builder and instruction input to each response card in the full editor. For conditions, reuse the existing `<.condition_builder>` component. For instructions, use the existing plain-text `<input>` for now (the proper instruction builder with assignments array will be added in Gap 5/Document 04). This keeps the full editor at feature parity with the current sidebar.

**Files affected:**

| File                                                               | Change                                                              |
|--------------------------------------------------------------------|---------------------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` | Add condition builder + instruction input inside each response card |

**Implementation steps:**

1. Import the condition builder component at the top of the module:
   ```elixir
   import StoryarnWeb.Components.ConditionBuilder
   ```

2. Inside each response card (after the text input row from Subtask 5), add a collapsible section:
   ```elixir
   <details class="collapse collapse-arrow bg-base-100 mt-2">
     <summary class="collapse-title text-xs py-1 min-h-0 cursor-pointer">
       {dgettext("flows", "Advanced")}
       <span :if={has_advanced?(response)} class="badge badge-warning badge-xs ml-1" />
     </summary>
     <div class="collapse-content space-y-3 pt-2">
       <!-- Condition -->
       <div class="space-y-1">
         <div class="flex items-center gap-1 text-xs text-base-content/60">
           <.icon name="git-branch" class="size-3" />
           <span>{dgettext("flows", "Condition")}</span>
         </div>
         <.condition_builder
           id={"screenplay-response-cond-#{response["id"]}"}
           condition={parse_response_condition(response)}
           variables={@project_variables}
           can_edit={@can_edit}
           context={%{"response-id" => response["id"], "node-id" => to_string(@node.id)}}
         />
       </div>
       <!-- Instruction (plain text for now, upgraded in Gap 5) -->
       <div class="flex items-center gap-2">
         <.icon name="zap" class="size-3 text-base-content/50 flex-shrink-0" />
         <input
           type="text"
           value={response["instruction"]}
           phx-blur="update_response_instruction_sp"
           phx-target={@myself}
           phx-value-response-id={response["id"]}
           phx-value-node-id={to_string(@node.id)}
           disabled={!@can_edit}
           placeholder={dgettext("flows", "Instruction (optional)")}
           class="input input-xs input-bordered flex-1 font-mono text-xs"
         />
       </div>
     </div>
   </details>
   ```

3. Add helper functions:
   ```elixir
   defp has_advanced?(response) do
     cond = response["condition"]
     inst = response["instruction"]
     (cond != nil and cond != "") or (inst != nil and inst != "")
   end

   defp parse_response_condition(response) do
     case Condition.parse(response["condition"] || "") do
       :legacy -> Condition.new()
       nil -> Condition.new()
       cond_data -> cond_data
     end
   end
   ```

4. Add the `project_variables` assign to the component. Update the caller in `show.ex` to pass it:
   ```elixir
   <.live_component
     ...
     project_variables={@project_variables}
   />
   ```

5. Add event handler for the instruction blur:
   ```elixir
   def handle_event("update_response_instruction_sp", params, socket) do
     send(self(), {:screenplay_event, "update_response_instruction", %{
       "response-id" => params["response-id"],
       "node-id" => params["node-id"],
       "value" => params["value"] || ""
     }})
     {:noreply, socket}
   end
   ```

6. In `show.ex`, add the `handle_info` clause for `update_response_instruction`:
   ```elixir
   def handle_info({:screenplay_event, "update_response_instruction", params}, socket) do
     case authorize(socket, :edit_content) do
       :ok -> Dialogue.Node.handle_update_response_instruction(params, socket)
       {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
     end
   end
   ```

7. The `update_response_condition_builder` event is already handled globally in `show.ex` (line 499-503) -- the condition builder hook pushes directly to the parent LiveView, not to the LiveComponent. So no extra wiring is needed for conditions.

**Test battery:**

| Test                                    | Location                                                                  | What it verifies                                                 |
|-----------------------------------------|---------------------------------------------------------------------------|------------------------------------------------------------------|
| Condition builder renders per response  | `/test/storyarn_web/live/flow_live/components/screenplay_editor_test.exs` | Each response card contains a `condition-builder` hook element   |
| Instruction input renders per response  | Same file                                                                 | Each response card contains an instruction input with `phx-blur` |
| Advanced badge shown when condition set | Same file                                                                 | Response with a condition shows the warning badge                |
| Advanced badge hidden when empty        | Same file                                                                 | Response without condition/instruction does not show badge       |
| Instruction update proxied to parent    | Integration test                                                          | Blurring instruction input triggers the parent handler           |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 7: Settings gear popover -- menu text and secondary fields

**Description:** Add a "Settings" gear button to the full editor header that opens a popover with secondary fields: menu text, audio picker, technical ID + generate button, localization ID + copy button. These are fields that are rarely changed after initial setup.

**Files affected:**

| File                                                               | Change                                                                                       |
|--------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` | Add settings gear button to header, popover with menu text + audio picker + technical fields |

**Implementation steps:**

1. In the header, between the spacer and close button, add:
   ```elixir
   <div class="relative">
     <button
       type="button"
       class="btn btn-ghost btn-sm btn-square"
       phx-click={JS.toggle(to: "#screenplay-settings-popover", display: "block")}
       title={dgettext("flows", "Settings")}
     >
       <.icon name="settings" class="size-4" />
     </button>
     <div
       id="screenplay-settings-popover"
       class="absolute right-0 top-full mt-1 w-72 bg-base-100 border border-base-300 rounded-lg shadow-lg z-50 p-4 space-y-4"
       style="display:none"
       phx-click-away={JS.hide(to: "#screenplay-settings-popover")}
     >
       <!-- Menu Text -->
       <div class="form-control">
         <label class="label"><span class="label-text text-xs">{dgettext("flows", "Menu Text")}</span></label>
         <input ... phx-blur="update_menu_text" phx-target={@myself} />
         <p class="text-xs text-base-content/60 mt-1">{dgettext("flows", "Optional shorter text for dialogue choice menus.")}</p>
       </div>
       <!-- Audio -->
       <div class="form-control">
         <label class="label"><span class="label-text text-xs">{dgettext("flows", "Audio")}</span></label>
         <.live_component module={AudioPicker} ... />
       </div>
       <!-- Technical ID -->
       <div class="form-control">
         <label class="label"><span class="label-text text-xs">{dgettext("flows", "Technical ID")}</span></label>
         <div class="join w-full">
           <input type="text" ... phx-blur="update_technical_id" phx-target={@myself} />
           <button :if={@can_edit} type="button" phx-click="generate_technical_id" class="btn btn-sm btn-ghost join-item">
             <.icon name="refresh-cw" class="size-3" />
           </button>
         </div>
       </div>
       <!-- Localization ID -->
       <div class="form-control">
         <label class="label"><span class="label-text text-xs">{dgettext("flows", "Localization ID")}</span></label>
         <div class="join w-full">
           <input type="text" ... disabled class="input input-sm input-bordered join-item flex-1 font-mono text-xs" />
           <button type="button" data-copy-text={@form[:localization_id].value || ""} class="btn btn-sm btn-ghost join-item">
             <.icon name="copy" class="size-3" />
           </button>
         </div>
       </div>
     </div>
   </div>
   ```

2. Add event handlers for `update_menu_text` and `update_technical_id` that proxy to the parent via field updates:
   ```elixir
   def handle_event("update_menu_text", %{"value" => value}, socket) do
     update_node_field(socket, "menu_text", value)
   end

   def handle_event("update_technical_id", %{"value" => value}, socket) do
     update_node_field(socket, "technical_id", value)
   end
   ```

3. The `generate_technical_id` event is already handled in `show.ex` (line 420-438) and pushes to the parent LiveView, not to `@myself`. So the button should use `phx-click="generate_technical_id"` **without** `phx-target={@myself}` to let it bubble up to the parent.

4. Import `alias Phoenix.LiveView.JS` if not already imported.

5. Import `alias StoryarnWeb.Components.AudioPicker` for the audio picker live component.

**Test battery:**

| Test                                               | Location                                                                  | What it verifies                              |
|----------------------------------------------------|---------------------------------------------------------------------------|-----------------------------------------------|
| Settings gear button renders                       | `/test/storyarn_web/live/flow_live/components/screenplay_editor_test.exs` | Header contains button with "settings" icon   |
| Popover contains menu text field                   | Same file                                                                 | Rendered HTML includes "Menu Text" label      |
| Popover contains audio section                     | Same file                                                                 | Contains audio picker component               |
| Popover contains technical ID with generate button | Same file                                                                 | Contains "Technical ID" and "refresh-cw" icon |
| Popover contains localization ID with copy         | Same file                                                                 | Contains "Localization ID" and "copy" icon    |
| Menu text update saves                             | Integration test                                                          | Blurring menu text input updates node data    |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 8: Integration and cleanup -- update editing_mode flow, remove/minimize dialogue sidebar

**Description:** Wire everything together. Update the editing mode flow so that dialogue nodes use the floating toolbar + full editor pattern. The sidebar becomes a thin fallback for non-dialogue node types. Clean up removed/dead code.

**Files affected:**

| File                                                                 | Change                                                                                                    |
|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| `/lib/storyarn_web/live/flow_live/show.ex`                           | Update `@editing_mode` flow for dialogue: selection shows toolbar, double-click or Edit opens full editor |
| `/lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Adjust `handle_node_selected` for dialogue to not open sidebar                                            |
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex`            | Update `on_double_click/1` return value if needed                                                         |
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex`  | Minimize or mark as deprecated                                                                            |
| `/lib/storyarn_web/live/flow_live/components/properties_panels.ex`   | Footer cleanup: remove "Open Screenplay" button (replaced by toolbar Edit button)                         |

**Implementation steps:**

1. **Editing mode for dialogue nodes:**
   - When a dialogue node is selected: set `@editing_mode` to `:toolbar` (new mode) instead of `:sidebar`. The floating toolbar is visible, but no side panel opens.
   - When Edit button (toolbar) or double-click occurs: set `@editing_mode` to `:screenplay` (existing mode). Full editor opens.
   - For non-dialogue node types: keep existing `:sidebar` behavior unchanged.

2. In `show.ex` render:
   - The floating toolbar container (from Subtask 3) renders when `@editing_mode == :toolbar`.
   - The sidebar renders when `@editing_mode == :sidebar`.
   - The full editor renders when `@editing_mode == :screenplay`.
   - Update the `:if` conditions accordingly.

3. In `GenericNodeHandlers.handle_node_selected/2`:
   - After getting the node, check type:
     ```elixir
     editing_mode = if node.type == "dialogue", do: :toolbar, else: :sidebar
     ```
   - Use this value in the assign instead of hard-coded `:sidebar`.

4. In `properties_panels.ex` footer:
   - Remove the "Open Screenplay" button (dialogue nodes no longer use the sidebar).
   - Remove the "Preview from here" button (moved to floating toolbar).
   - The footer now only contains empty space for non-entry, non-dialogue types (or could be removed entirely if empty).

5. `dialogue/config_sidebar.ex`:
   - Keep the file but add a deprecation note in the moduledoc.
   - It may still be useful as a fallback or for testing. Do not delete it yet.
   - Alternatively, if you want a clean break: remove the sidebar module from `NodeTypeRegistry.@sidebar_modules` for `"dialogue"`. The `node_sidebar_content/1` in `properties_panels.ex` will render `default_sidebar/1` ("No properties for this node type") if the sidebar module is `nil`.

6. Verify that all `handle_info` clauses for `{:screenplay_event, ...}` from Subtask 5 and 6 are present.

7. Verify keyboard shortcuts still work:
   - Delete/Backspace deletes dialogue node from toolbar mode.
   - Escape deselects (hides toolbar).
   - Double-click opens full editor.

**Test battery:**

| Test                                      | Location                                                 | What it verifies                                                                    |
|-------------------------------------------|----------------------------------------------------------|-------------------------------------------------------------------------------------|
| Dialogue node selection sets toolbar mode | `/test/storyarn_web/live/flow_live/show_events_test.exs` | After `node_selected` for dialogue node, `socket.assigns.editing_mode == :toolbar`  |
| Non-dialogue node selection keeps sidebar | Same file                                                | After `node_selected` for condition node, `socket.assigns.editing_mode == :sidebar` |
| Double-click dialogue opens full editor   | Same file                                                | After `node_double_clicked` for dialogue, `editing_mode == :screenplay`             |
| Toolbar Edit button opens full editor     | Same file                                                | After `open_screenplay` event, `editing_mode == :screenplay`                        |
| Close editor returns to nil               | Same file                                                | After `close_editor`, `editing_mode == nil`                                         |
| Deselect hides toolbar                    | Same file                                                | After `deselect_node`, `editing_mode == nil` and `selected_node == nil`             |
| Sidebar does not render for dialogue      | Integration                                              | When dialogue selected, page does **not** contain `w-80` aside                      |
| Full editor renders speaker + responses   | Integration                                              | When in screenplay mode, page contains two-column layout with responses             |
| No regression: condition node sidebar     | Integration                                              | Condition node sidebar still renders condition builder                              |

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary of file changes across all subtasks

| File                                                                 | Subtasks      | Type                 |
|----------------------------------------------------------------------|---------------|----------------------|
| `/lib/storyarn_web/live/flow_live/components/properties_panels.ex`   | 1, 8          | Modified             |
| `/assets/js/flow_canvas/floating_toolbar.js`                         | 2             | **New**              |
| `/assets/js/hooks/flow_canvas.js`                                    | 2             | Modified             |
| `/assets/js/flow_canvas/event_bindings.js`                           | 2             | Modified             |
| `/lib/storyarn_web/live/flow_live/components/dialogue_toolbar.ex`    | 3             | **New**              |
| `/assets/js/hooks/flow_floating_toolbar.js`                          | 3             | **New**              |
| `/assets/js/hooks/index.js`                                          | 3             | Modified             |
| `/lib/storyarn_web/live/flow_live/components/screenplay_editor.ex`   | 4, 5, 6, 7    | Modified             |
| `/lib/storyarn_web/live/flow_live/show.ex`                           | 3, 4, 5, 6, 8 | Modified             |
| `/lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | 8             | Modified             |
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex`            | 8             | Modified (minor)     |
| `/lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex`  | 8             | Deprecated/minimized |
| `/lib/storyarn_web/live/flow_live/node_type_registry.ex`             | 8             | Modified (optional)  |

---

**Next document:** [`04_EXPRESSION_SYSTEM.md`](./04_EXPRESSION_SYSTEM.md) -- Expression System: Code Editor + Visual Builder
