# 03 — Node UX Redesign: Floating Toolbar + Context Menu + Full Editor

| Field         | Value                                                            |
|---------------|------------------------------------------------------------------|
| Gap Reference | Gaps 3 + 4 from `COMPLEX_NARRATIVE_STRESS_TEST.md`               |
| Priority      | HIGH                                                             |
| Effort        | High                                                             |
| Dependencies  | None                                                             |
| Absorbs       | `02_CREATE_LINKED_FLOW.md` (deleted after this plan is complete) |
| Previous      | `01_NESTED_CONDITIONS.md`                                        |
| Next          | [`04_EXPRESSION_SYSTEM.md`](04_EXPRESSION_SYSTEM.md)           |
| Last Updated  | February 20, 2026                                                |

---

## Context and Current State

### The problem

All 9 node types use a **320px sidebar panel** for editing. This has issues:

1. **Canvas occlusion** — the sidebar eats 320px of horizontal space, pushing the canvas
2. **One-size-fits-all** — entry shows 3 lines of info text in 320px; dialogue crams speaker, text editor, responses with conditions/instructions, menu text, audio, and technical IDs into the same 320px
3. **No context menu** — the map editor already has right-click context menus per element type; the flow editor has none
4. **No floating toolbar** — the map editor has floating toolbars per element type with inline editing; the flow editor has none
5. **Dialogue editing friction** — the screenplay editor is fullscreen but read-only for responses ("Edit responses in the sidebar panel"), forcing users to switch between two modes

### What replaces it

| Interaction               | What happens                            | Applies to                       |
|---------------------------|-----------------------------------------|----------------------------------|
| **Single click**          | Floating toolbar appears above the node | All 9 types                      |
| **Right click**           | Context menu appears at cursor          | All 9 types                      |
| **Double click**          | Full editor opens (fullscreen overlay)  | Dialogue only (others → toolbar) |
| **Toolbar "Edit" button** | Full editor opens                       | Dialogue only                    |

The sidebar (`properties_panels.ex`) is **removed entirely**. Zero side panel.

### Editing modes

| Current       | New        | Description                                                  |
|---------------|------------|--------------------------------------------------------------|
| `nil`         | `nil`      | No selection, canvas only                                    |
| `:sidebar`    | `:toolbar` | Node selected, floating toolbar visible, canvas fully usable |
| `:screenplay` | `:editor`  | Dialogue full editor (fullscreen overlay)                    |
| —             | `:builder` | Condition/instruction builder panel open below toolbar       |

### Reference implementations

| Pattern           | Source files                                                                                                |
|-------------------|-------------------------------------------------------------------------------------------------------------|
| Floating toolbar  | `assets/js/scene_canvas/floating_toolbar.js`, `lib/storyarn_web/live/scene_live/components/floating_toolbar.ex` |
| Context menu      | `assets/js/scene_canvas/context_menu.js`, `assets/js/scene_canvas/context_menu_builder.js`                      |
| Per-type dispatch | `lib/storyarn_web/live/scene_live/components/floating_toolbar.ex` (zone_toolbar, pin_toolbar, etc.)           |

### Current key files

| File                                                                | Role                                                              |
|---------------------------------------------------------------------|-------------------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex`   | 320px sidebar — **to be deleted**                                 |
| `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex`   | Fullscreen dialogue editor — **to be evolved into two-panel**     |
| `lib/storyarn_web/live/flow_live/node_type_registry.ex`             | Type → module dispatch (has `@sidebar_modules` — to be removed)   |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Selection, double-click, close, delete handlers                   |
| `lib/storyarn_web/live/flow_live/show.ex`                           | Main LiveView render + event routing                              |
| `assets/js/flow_canvas/handlers/keyboard_handler.js`                | Keyboard shortcuts (Delete, Escape, Ctrl+D, etc.)                 |
| `lib/storyarn_web/live/flow_live/nodes/*/node.ex`                   | Per-type metadata, event handlers, `on_select`, `on_double_click` |
| `lib/storyarn_web/live/flow_live/nodes/*/config_sidebar.ex`         | Per-type sidebar content — **to be deprecated**                   |

---

## Node Type Classification

| Category    | Types                     | Toolbar                                     | Context Menu                                  | Full Editor                     |
|-------------|---------------------------|---------------------------------------------|-----------------------------------------------|---------------------------------|
| **Info**    | entry                     | Read-only info + badges                     | View referencing flows                        | No                              |
| **Simple**  | jump                      | Select + locate button                      | Delete, Duplicate                             | No                              |
| **Medium**  | hub, exit, subflow, scene | Inline fields + popovers                    | Delete, Duplicate, Navigate, Create Flow      | No                              |
| **Complex** | dialogue                  | Summary + "Edit" button                     | Delete, Duplicate, Edit, Preview, Generate ID | Yes (two-panel)                 |
| **Builder** | condition, instruction    | Summary + "Edit" button opens builder panel | Delete, Duplicate                             | Builder panel (not full editor) |

### Builder panel concept

Condition and instruction nodes have complex builders (condition_builder, instruction_builder) that don't fit in a toolbar popover but don't need a full two-panel editor either. When the user clicks "Edit" in their toolbar, a **builder panel** opens — a focused floating panel (not fullscreen, not sidebar) anchored below the toolbar, containing just the builder widget. Clicking outside or pressing Escape closes it.

---

## Floating Toolbar Content per Type

### Entry
```
┌──────────────────────────────────────┐
│ ▶ Entry point   [3 refs]             │
└──────────────────────────────────────┘
```
- Play icon + "Entry point" label (read-only)
- Referenced-by count badge → click navigates to referencing flow list (popover)

### Exit
```
┌───────────────────────────────────────────────────────────────┐
│ [label input  ] [Terminal ▪ Flow ▪ Return] [🟢] [⚙]          │
└───────────────────────────────────────────────────────────────┘
```
- Label text input (inline, blur saves)
- Exit mode pills: Terminal / Flow / Return (click switches)
- Color dot (click opens color picker popover)
- Gear icon → settings popover: outcome tags, technical ID + generate, referenced-by list
- **When flow_reference mode and flow assigned**: flow name badge + "Open" button replaces label area
- **When flow_reference mode and no flow**: "Create flow" button (from absorbed 02)

### Dialogue
```
┌────────────────────────────────────────────────────────────────┐
│ [Speaker ▾] [🔊] [3 responses] [✏ Edit] [▶ Preview]          │
└────────────────────────────────────────────────────────────────┘
```
- Speaker `<select>` (compact, select-xs)
- Audio indicator icon (visible only when audio_asset_id is set)
- Response count badge
- "Edit" button → opens full editor
- "Preview" button → starts preview at this node

### Condition
```
┌──────────────────────────────────────────────────────────┐
│ ◇ Condition  [Switch: off] [2 rules / 1 block] [✏ Edit] │
└──────────────────────────────────────────────────────────┘
```
- Git-branch icon + "Condition" label
- Switch mode toggle (inline checkbox/pill)
- Summary: rule/block count
- "Edit" button → opens builder panel below toolbar with condition_builder

### Instruction
```
┌──────────────────────────────────────────────────────────┐
│ ⚡ Instruction  [3 assignments] [✏ Edit]                  │
└──────────────────────────────────────────────────────────┘
```
- Zap icon + "Instruction" label
- Assignment count
- "Edit" button → opens builder panel below toolbar with instruction_builder
- Description text shown as subtitle if present

### Hub
```
┌──────────────────────────────────────────────────────────┐
│ [label input] [hub_id input] [🟣] [2 jumps]              │
└──────────────────────────────────────────────────────────┘
```
- Label text input (inline)
- Hub ID text input (inline, required indicator)
- Color dot (click opens color picker)
- Jump count badge → click opens popover with referencing jumps list + "Locate all"

### Jump
```
┌──────────────────────────────────────────────────────────┐
│ ↗ Jump to: [Target Hub ▾] [📍 Locate]                    │
└──────────────────────────────────────────────────────────┘
```
- Target hub `<select>` (inline)
- "Locate" button → navigates to target hub on canvas
- Warning text if no hubs exist

### Subflow
```
┌──────────────────────────────────────────────────────────┐
│ 📦 [Flow ▾ / Flow Name] [↗ Open] [3 exits]               │
└──────────────────────────────────────────────────────────┘
```
- Box icon
- Flow `<select>` (if no flow set) or flow name badge (if set)
- "Open" button → navigates to subflow
- "Create flow" button (if no flow set, from absorbed 02)
- Exit count badge → popover showing exit nodes with labels/colors

### Scene
```
┌──────────────────────────────────────────────────────────┐
│ 🎬 [Location ▾] [INT ▪ EXT] [Time ▾] [⚙]                │
└──────────────────────────────────────────────────────────┘
```
- Clapperboard icon
- Location `<select>` (inline)
- Int/Ext pills
- Time of day `<select>` (inline)
- Gear icon → settings popover: sub-location, description, technical ID + generate

---

## Context Menu per Type

### Common items (all types except entry)
```
────────────────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

### Entry
```
────────────────────
  ↗ View referencing flows (N)
────────────────────
```

### Dialogue
```
────────────────────
  ✏ Edit                     (opens full editor)
  ▶ Preview from here
  ──────────
  #  Generate technical ID
  ──────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

### Condition
```
────────────────────
  🔀 Toggle switch mode
  ──────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

### Instruction
```
────────────────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

### Hub
```
────────────────────
  📍 Locate referencing jumps (N)
  ──────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

### Jump
```
────────────────────
  📍 Locate target hub
  ──────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

### Exit
```
────────────────────
  ↗ Open referenced flow      (when flow set)
  + Create linked flow         (when flow_reference, no flow)
  ──────────
  #  Generate technical ID
  ──────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

### Subflow
```
────────────────────
  ↗ Open subflow               (when flow set)
  + Create linked flow          (when no flow set)
  ──────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

### Scene
```
────────────────────
  #  Generate technical ID
  ──────────
  ✂ Duplicate
  🗑 Delete
────────────────────
```

---

## Dialogue Full Editor (Two-Panel)

Replaces the current `ScreenplayEditor`. Fullscreen overlay (`fixed inset-0 z-50`).

```
┌─ HEADER ────────────────────────────────────────────────────────────┐
│  [← Back to canvas]                                           [X]  │
└─────────────────────────────────────────────────────────────────────┘

┌─ LEFT PANEL (screenplay) ─────────┬─ RIGHT PANEL (tabs) ───────────┐
│                                    │                                 │
│  CHARACTER NAME (speaker select)   │  [Responses] [Settings]         │
│  (stage directions)                │                                 │
│                                    │  ┌─ Responses tab ────────────┐│
│  Dialogue text...                  │  │                             ││
│  (TipTap rich text editor)         │  │  Response 1                 ││
│                                    │  │  [text input         ] [X]  ││
│                                    │  │  ▸ Advanced                 ││
│                                    │  │    Condition: builder       ││
│                                    │  │    Instruction: input       ││
│                                    │  │                             ││
│                                    │  │  Response 2                 ││
│                                    │  │  [text input         ] [X]  ││
│                                    │  │  ▸ Advanced                 ││
│                                    │  │                             ││
│                                    │  │  [+ Add response]           ││
│                                    │  └─────────────────────────────┘│
│                                    │                                 │
│                                    │  ┌─ Settings tab (hidden) ────┐│
│                                    │  │  Menu text                  ││
│                                    │  │  Audio picker               ││
│                                    │  │  Technical ID + generate    ││
│                                    │  │  Localization ID + copy     ││
│                                    │  └─────────────────────────────┘│
└────────────────────────────────────┴─────────────────────────────────┘

┌─ FOOTER ────────────────────────────────────────────────────────────┐
│  [👤 Speaker Name]  [📄 N words]  [🔊 audio.mp3]        [Esc] close │
└─────────────────────────────────────────────────────────────────────┘
```

**Left panel**: Screenplay-style. Speaker select at top, stage directions in parenthetical style, TipTap editor for dialogue text. Same aesthetic as current screenplay editor.

**Right panel tabs:**
- **Responses**: Response cards with text input, collapsible "Advanced" per response (condition builder + instruction input). Yellow dot indicator when advanced is set. "Add response" button at bottom.
- **Settings**: Menu text, audio picker (AudioPicker LiveComponent), technical ID with generate button, localization ID with copy button.

**Header**: "Back to canvas" (closes editor), X close button.

**Footer**: Speaker name, word count, audio filename (if set), "Esc to close" hint.

---

## Subtasks

### Subtask 1: Context menu infrastructure (JS)

**Description:** Adapt `assets/js/scene_canvas/context_menu.js` for the flow canvas. Create a positioned menu that appears on right-click, with per-type items.

**New files:**

| File                                          | Role                                                         |
|-----------------------------------------------|--------------------------------------------------------------|
| `assets/js/flow_canvas/context_menu.js`       | `createFlowContextMenu(hook)` → `{show, hide}`               |
| `assets/js/flow_canvas/context_menu_items.js` | `getContextMenuItems(nodeType, nodeData, hook)` → item array |

**Modified files:**

| File                                      | Change                                                                      |
|-------------------------------------------|-----------------------------------------------------------------------------|
| `assets/js/hooks/flow_canvas.js`          | Instantiate context menu, wire right-click on nodes                         |
| `assets/js/flow_canvas/event_bindings.js` | Listen for `contextmenu` event on node views, suppress default browser menu |

**Implementation:**

1. Create `context_menu.js`: Same pattern as map — `show(x, y, items)` renders a positioned `<div>` with menu items. `hide()` removes it. Listens for click-outside and Escape to auto-hide. CSS: `absolute z-[9999] bg-base-100 border border-base-300 rounded-lg shadow-lg py-1 min-w-[160px]`.

2. Create `context_menu_items.js`: Export `getContextMenuItems(nodeType, nodeData, hook)` that returns an array of `{label, icon, action, separator?, disabled?}` objects per type. `action` is a closure that calls `hook.pushEvent(eventName, payload)`. Icons use Lucide `createElement()`. Menu items match the "Context Menu per Type" section above.

3. In `flow_canvas.js` `initEditor()`: Instantiate `this.contextMenu = createFlowContextMenu(this)`.

4. In `event_bindings.js`: Attach `contextmenu` handler to the area's container. On right-click, check if click target is inside a node view element. If yes: get node ID from the DOM element, get node data from the editor, call `getContextMenuItems(type, data, hook)`, call `contextMenu.show(event.clientX, event.clientY, items)`. If no: hide context menu.

5. Events pushed to server: All existing events — `delete_node`, `duplicate_node`, `generate_technical_id`, `toggle_switch_mode`, `start_preview`, `navigate_to_exit_flow`, `navigate_to_subflow`, `navigate_to_hub`, `open_screenplay`, `create_linked_flow`. No new backend events needed except `create_linked_flow` (Subtask 6).

**Test battery:**

| Test                                                                                         | What it verifies                               |
|----------------------------------------------------------------------------------------------|------------------------------------------------|
| `context_menu.js` exports correct API                                                        | `createFlowContextMenu` returns `{show, hide}` |
| `getContextMenuItems("dialogue", ...)` returns Edit, Preview, Generate ID, Duplicate, Delete | Correct items for dialogue                     |
| `getContextMenuItems("entry", ...)` does NOT include Delete or Duplicate                     | Entry protection                               |
| Context menu hides on click outside                                                          | Auto-dismiss                                   |
| Context menu hides on Escape                                                                 | Auto-dismiss                                   |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 2: Floating toolbar infrastructure (JS)

**Description:** Adapt `assets/js/scene_canvas/floating_toolbar.js` for Rete.js coordinates. Position a toolbar element above the selected node, repositioning on pan/zoom/drag.

**New files:**

| File                                        | Role                                                                        |
|---------------------------------------------|-----------------------------------------------------------------------------|
| `assets/js/flow_canvas/floating_toolbar.js` | `createFlowFloatingToolbar(hook)` → `{show, hide, reposition, setDragging}` |
| `assets/js/hooks/flow_floating_toolbar.js`  | LiveView hook for post-patch repositioning                                  |

**Modified files:**

| File                                      | Change                                                                           |
|-------------------------------------------|----------------------------------------------------------------------------------|
| `assets/js/hooks/flow_canvas.js`          | Instantiate toolbar, wire show/hide/reposition                                   |
| `assets/js/flow_canvas/event_bindings.js` | Wire `area:translate`, `area:zoom` → `reposition()`; node drag → `setDragging()` |
| `assets/js/hooks/index.js`                | Register `FlowFloatingToolbar` hook                                              |

**Implementation:**

1. `floating_toolbar.js`: Same API as map version. Core difference: instead of Leaflet `latLngToContainerPoint`, use Rete.js node view's `getBoundingClientRect()` to get screen coordinates. Position toolbar centered horizontally above the node, offset by 12px. Clamp to canvas bounds. Flip below if too close to top.

2. `flow_floating_toolbar.js` hook:
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

3. In `flow_canvas.js` `initEditor()`: `this.floatingToolbar = createFlowFloatingToolbar(this)`. Store ref: `this.el.__floatingToolbar = this.floatingToolbar`.

4. On node selection (JS side): `this.floatingToolbar.show(nodeId)`.

5. On deselection: `this.floatingToolbar.hide()`.

6. On area pan/zoom: `this.floatingToolbar.reposition()`.

7. On node drag start: `this.floatingToolbar.setDragging(true)`. On drag end: `this.floatingToolbar.setDragging(false)`.

8. Visibility: CSS class `toolbar-visible` (same as map), never inline `display`, to avoid morphdom conflicts.

**Test battery:**

| Test                                                   | What it verifies                                    |
|--------------------------------------------------------|-----------------------------------------------------|
| Module exports `{show, hide, reposition, setDragging}` | Correct API                                         |
| Toolbar hidden when no node selected                   | No `toolbar-visible` class on load                  |
| Toolbar appears on node selection                      | `toolbar-visible` class added, positioned near node |
| Toolbar repositions on pan/zoom                        | `reposition()` updates position                     |
| Toolbar hides during drag                              | `setDragging(true)` removes `toolbar-visible`       |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 3: Floating toolbar HEEx container + per-type dispatch

**Description:** Create the server-rendered toolbar component with per-type content. Add the toolbar container to the flow editor layout.

**New files:**

| File                                                         | Role                                 |
|--------------------------------------------------------------|--------------------------------------|
| `lib/storyarn_web/live/flow_live/components/flow_toolbar.ex` | Per-type toolbar function components |

**Modified files:**

| File                                      | Change                                   |
|-------------------------------------------|------------------------------------------|
| `lib/storyarn_web/live/flow_live/show.ex` | Add toolbar container inside canvas area |

**Implementation:**

1. In `show.ex`, inside the canvas container `<div class="flex-1 relative bg-base-200">`, after `#flow-canvas`, add:
   ```elixir
   <div
     id="flow-floating-toolbar"
     phx-hook="FlowFloatingToolbar"
     class="floating-toolbar absolute z-30 pointer-events-none"
   >
     <div
       :if={@selected_node && @editing_mode in [:toolbar, :builder]}
       class="pointer-events-auto bg-base-100 border border-base-300 rounded-lg shadow-lg px-2 py-1.5"
     >
       <.node_toolbar
         node={@selected_node}
         form={@node_form}
         can_edit={@can_edit}
         all_sheets={@all_sheets}
         flow_hubs={@flow_hubs}
         available_flows={@available_flows}
         subflow_exits={@subflow_exits}
         referencing_jumps={@referencing_jumps}
         referencing_flows={@referencing_flows}
         outcome_tags_suggestions={@outcome_tags_suggestions}
       />
     </div>
   </div>
   ```

2. `flow_toolbar.ex`: Main dispatch function `node_toolbar/1` pattern-matches on `@node.type` and delegates to type-specific function components: `entry_toolbar/1`, `exit_toolbar/1`, `dialogue_toolbar/1`, `condition_toolbar/1`, `instruction_toolbar/1`, `hub_toolbar/1`, `jump_toolbar/1`, `subflow_toolbar/1`, `scene_toolbar/1`.

3. Each toolbar renders as `<div class="flex items-center gap-1.5">` with controls as described in the "Floating Toolbar Content per Type" section.

4. Events fire existing server events: `update_node_data`, `update_exit_mode`, `update_exit_reference`, `update_subflow_reference`, `update_hub_color`, `update_outcome_color`, `open_screenplay`, `start_preview`, `create_linked_flow`, `navigate_to_exit_flow`, `navigate_to_subflow`, `navigate_to_hub`, etc.

5. Shared toolbar widgets (reusable across types):
   - `toolbar_color_picker/1` — for hub, exit
   - `toolbar_popover/1` — generic popover wrapper for settings gear

**Test battery:**

| Test                                                                  | What it verifies      |
|-----------------------------------------------------------------------|-----------------------|
| `node_toolbar` renders for all 9 node types                           | No crash for any type |
| Dialogue toolbar contains speaker select, Edit button, Preview button | Correct controls      |
| Exit toolbar contains label input, exit mode pills                    | Correct controls      |
| Condition toolbar contains switch mode toggle, Edit button            | Correct controls      |
| Hub toolbar contains label input, hub_id input, color picker          | Correct controls      |
| Jump toolbar contains target hub select, Locate button                | Correct controls      |
| Subflow toolbar contains flow select/name, Open button                | Correct controls      |
| Entry toolbar is read-only                                            | No editable fields    |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 4: Builder panel for condition and instruction

**Description:** When condition or instruction toolbar's "Edit" button is clicked, a builder panel opens — a focused floating panel anchored below the toolbar, containing the respective builder widget. Not fullscreen, not sidebar.

**New files:**

| File                                                          | Role                                 |
|---------------------------------------------------------------|--------------------------------------|
| `lib/storyarn_web/live/flow_live/components/builder_panel.ex` | Wrapper component for builder panels |

**Modified files:**

| File                                      | Change                                                               |
|-------------------------------------------|----------------------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/show.ex` | Add builder panel container, add `:builder` editing mode transitions |

**Implementation:**

1. New editing mode: `:builder` — node selected, toolbar visible, builder panel visible below toolbar.

2. Builder panel container in `show.ex`, inside the toolbar container (positioned by same JS logic, offset further down):
   ```elixir
   <div
     :if={@selected_node && @editing_mode == :builder}
     class="pointer-events-auto mt-2 bg-base-100 border border-base-300 rounded-lg shadow-lg p-4 max-h-[60vh] overflow-y-auto w-[400px]"
   >
     <.builder_panel_content
       node={@selected_node}
       form={@node_form}
       can_edit={@can_edit}
       project_variables={@project_variables}
     />
   </div>
   ```

3. `builder_panel.ex` dispatches by type:
   - **Condition**: Title bar ("Condition Builder" + close button), switch mode toggle, `<.condition_builder>` component with full width
   - **Instruction**: Title bar ("Instruction Builder" + close button), description input, `<.instruction_builder>` component

4. Events: `open_builder` (new, sets `:builder` mode), `close_builder` (new, returns to `:toolbar`). Close triggers: close button, Escape key, click outside panel.

5. Changes push through existing handlers: `update_condition_builder`, `update_instruction_builder`, `toggle_switch_mode`.

**Editing mode transitions:**

| From       | To         | Trigger                                       |
|------------|------------|-----------------------------------------------|
| `:toolbar` | `:builder` | Click "Edit" on condition/instruction toolbar |
| `:builder` | `:toolbar` | Escape, click outside, close button           |
| `:builder` | `nil`      | Click on empty canvas (deselect)              |

**Test battery:**

| Test                                                      | What it verifies                       |
|-----------------------------------------------------------|----------------------------------------|
| Builder panel renders for condition node                  | Contains condition_builder component   |
| Builder panel renders for instruction node                | Contains instruction_builder component |
| Builder panel has close button                            | Title bar with X button                |
| `close_builder` event returns to `:toolbar` mode          | Mode transition                        |
| Condition builder changes push `update_condition_builder` | Existing event reuse                   |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 5: Dialogue full editor (two-panel)

**Description:** Evolve `screenplay_editor.ex` into the two-panel layout. Left panel: screenplay-style content. Right panel: tabbed interface with Responses and Settings tabs.

**Modified files:**

| File                                                              | Change                                                               |
|-------------------------------------------------------------------|----------------------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` | Major layout rework                                                  |
| `lib/storyarn_web/live/flow_live/show.ex`                         | Update ScreenplayEditor invocation, rename `:screenplay` → `:editor` |

**Implementation:**

1. **Layout**: Replace single-column with `grid grid-cols-1 lg:grid-cols-2 gap-6`:
   - Left: Speaker select, stage directions, TipTap editor (existing, restructured)
   - Right: Tab bar + tab content

2. **Right panel tabs** (DaisyUI tabs, CSS-only):
   - **Responses tab**: Response cards. Each card: text input with `phx-blur="update_response_text"`, remove X button with `phx-click="remove_response"`, collapsible "Advanced" section with:
     - Condition: `<.condition_builder>` with context `%{"response-id" => id, "node-id" => node_id}`
     - Instruction: text input with `phx-blur="update_response_instruction"`
     - Yellow indicator dot when condition or instruction is set
   - "Add response" dashed button at bottom
   - **Settings tab**: Menu text input, AudioPicker LiveComponent, technical ID + generate button, localization ID + copy button

3. **Header**: Remove "Open Sidebar" button. "Back to canvas" button (fires `close_editor`). X close button.

4. **Footer**: Speaker name, word count, audio filename (if set), "Esc to close".

5. **Events**: Response events proxied from LiveComponent to parent via `send(self(), {:screenplay_event, event, params})`:
   - `add_response`, `remove_response`, `update_response_text`, `update_response_condition`, `update_response_instruction`
   - Parent `handle_info` clauses delegate to existing `Dialogue.Node` handlers

6. Condition builder per response: `update_response_condition_builder` event already handled globally in show.ex — condition builder hook pushes directly to parent LiveView.

7. Update `show.ex`:
   - Remove `on_open_sidebar` prop
   - Pass `project_variables` for condition builders in responses
   - Rename `:screenplay` editing mode to `:editor`
   - Add `handle_info` clauses for `{:screenplay_event, ...}` that delegate to `Dialogue.Node` handlers

**Test battery:**

| Test                                          | What it verifies                           |
|-----------------------------------------------|--------------------------------------------|
| Two-column layout renders                     | HTML contains `grid-cols-2` class          |
| Speaker selector still works                  | Contains `<select` with speaker options    |
| Stage directions input renders                | Contains stage directions input            |
| TiptapEditor container renders                | Contains `phx-hook="TiptapEditor"`         |
| Response cards render in right panel          | Response text inputs present               |
| Add response button present                   | Contains "Add response"                    |
| Remove button present per response            | Each card has X button                     |
| Condition builder renders per response        | Contains `condition-builder` hook elements |
| Instruction input renders per response        | Contains instruction input with `phx-blur` |
| Settings tab contains menu text field         | "Menu Text" label present                  |
| Settings tab contains audio picker            | AudioPicker component present              |
| Settings tab contains technical ID + generate | "Technical ID" and generate button present |
| Footer shows word count                       | Footer contains word count text            |
| No "Open Sidebar" button                      | Does not contain "Open Sidebar" text       |
| "Back to canvas" button present               | Contains close/back button                 |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 6: Create Linked Flow backend (absorbed from 02)

**Description:** Add backend function to create a flow as a child of the current flow and assign it to a node's `referenced_flow_id`. Used by exit and subflow toolbar "Create flow" buttons and context menu items.

**Modified files:**

| File                                      | Change                                                   |
|-------------------------------------------|----------------------------------------------------------|
| `lib/storyarn/flows/flow_crud.ex`         | Add `create_linked_flow/4` + `derive_linked_flow_name/3` |
| `lib/storyarn/flows.ex`                   | Add `defdelegate create_linked_flow`                     |
| `lib/storyarn_web/live/flow_live/show.ex` | Add `handle_event("create_linked_flow", ...)`            |

**Implementation:**

1. `create_linked_flow/4` in `flow_crud.ex`: Single-transaction operation. Creates a flow with `parent_id` set to the current flow. Derives name from node label or falls back to `"#{parent_flow.name} - Sub"`. Updates the node's `referenced_flow_id`. Returns `{:ok, %{flow: flow, node: node}}`.

2. `defdelegate` in `flows.ex`.

3. `handle_event("create_linked_flow", %{"node-id" => node_id_str}, socket)` in `show.ex`: Validates auth, calls `Flows.create_linked_flow/4`, navigates to new flow by default (via `push_navigate` with `?from=` param).

**Test battery:**

| Test                                        | What it verifies                                                                  |
|---------------------------------------------|-----------------------------------------------------------------------------------|
| Creates child flow and assigns to exit node | `new_flow.parent_id == flow.id`, `node.data["referenced_flow_id"] == new_flow.id` |
| Uses node label as flow name                | `new_flow.name == "Victory"` when label is "Victory"                              |
| Uses fallback name when no label            | `new_flow.name == "#{flow.name} - Sub"`                                           |
| Uses explicit name when provided            | `new_flow.name == "Custom Name"`                                                  |
| Auto-generates shortcut                     | `new_flow.shortcut != nil`                                                        |
| New flow has Entry + Exit nodes             | 2 auto-created nodes                                                              |
| Tree position is correct                    | Second linked flow has higher position                                            |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 7: Remove sidebar, update editing modes, wire everything

**Description:** Remove the sidebar from the flow editor. Update all editing mode transitions. Wire toolbar, builder panel, full editor, and context menu together.

**Modified files:**

| File                                                                | Change                                                        |
|---------------------------------------------------------------------|---------------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/show.ex`                           | Remove sidebar rendering, update editing mode assigns         |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Change `:sidebar` to `:toolbar`, update double-click dispatch |
| `lib/storyarn_web/live/flow_live/node_type_registry.ex`             | Remove `@sidebar_modules` map and `sidebar_module/1` function |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex`   | **Delete file**                                               |

**Implementation:**

1. In `generic_node_handlers.ex`:
   - `handle_node_selected`: assign `editing_mode: :toolbar` (was `:sidebar`)
   - `handle_node_double_clicked`:
     - Dialogue → `:editor`
     - Condition, instruction → `:builder`
     - Subflow with `referenced_flow_id` → `{:navigate, flow_id}`
     - All others → `:toolbar`
   - Remove `handle_open_sidebar` or rename to `handle_open_builder`

2. In `show.ex` render:
   - **Remove** the `<.node_properties_panel>` block entirely
   - Layout becomes: canvas + debug panel only, no right column
   - Toolbar container renders inside canvas area (Subtask 3)
   - Builder panel renders inside toolbar container (Subtask 4)
   - Editor overlay renders when `@editing_mode == :editor` (Subtask 5)

3. Remove `handle_event("toggle_panel_section", ...)` — no more collapsible sections.

4. Remove `@panel_sections` assign.

5. Update `NodeTypeRegistry`:
   - Remove `@sidebar_modules` map
   - Remove `sidebar_module/1` function
   - Keep `@node_modules` and all other functions

6. Per-type `config_sidebar.ex` files: Add deprecation note to each. Do not delete yet (tests may reference them). Schedule deletion in cleanup pass.

7. Delete `properties_panels.ex`.

**Editing mode summary after wiring:**

| Mode       | What's visible                         | Trigger                                                                    |
|------------|----------------------------------------|----------------------------------------------------------------------------|
| `nil`      | Canvas only                            | Page load, `close_editor`, `deselect_node`                                 |
| `:toolbar` | Floating toolbar above node            | `node_selected` (any type), `close_builder`                                |
| `:builder` | Floating toolbar + builder panel below | `open_builder` (condition/instruction), double-click condition/instruction |
| `:editor`  | Fullscreen two-panel editor            | `open_screenplay` / double-click dialogue / toolbar "Edit" on dialogue     |

**Test battery:**

| Test                                               | What it verifies                          |
|----------------------------------------------------|-------------------------------------------|
| Dialogue selection sets `:toolbar` mode            | `socket.assigns.editing_mode == :toolbar` |
| Condition selection sets `:toolbar` mode           | `socket.assigns.editing_mode == :toolbar` |
| Double-click dialogue opens `:editor`              | `socket.assigns.editing_mode == :editor`  |
| Double-click condition opens `:builder`            | `socket.assigns.editing_mode == :builder` |
| Double-click instruction opens `:builder`          | `socket.assigns.editing_mode == :builder` |
| Double-click subflow with ref navigates            | `push_navigate` called                    |
| Double-click hub stays at `:toolbar`               | `socket.assigns.editing_mode == :toolbar` |
| `close_editor` returns to `nil`                    | `socket.assigns.editing_mode == nil`      |
| `close_builder` returns to `:toolbar`              | `socket.assigns.editing_mode == :toolbar` |
| `deselect_node` returns to `nil`                   | `socket.assigns.editing_mode == nil`      |
| Sidebar does not render for any node type          | Page does not contain `w-80` aside        |
| No regression: all existing node events still work | Full event handler test pass              |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 8: Keyboard handler updates

**Description:** Update keyboard shortcuts for the new editing modes.

**Modified files:**

| File                                                 | Change                                       |
|------------------------------------------------------|----------------------------------------------|
| `assets/js/flow_canvas/handlers/keyboard_handler.js` | Update Escape behavior, add Enter/E shortcut |

**Implementation:**

1. **Escape** priority chain:
   - If editor is open → push `close_editor`
   - If builder panel is open → push `close_builder`
   - If node selected (toolbar visible) → push `deselect_node`

2. **Enter** or **E** (when node selected, not in editable field):
   - Dialogue → push `open_screenplay` (opens full editor)
   - Condition / instruction → push `open_builder` (opens builder panel)
   - Others → no-op

3. **Delete/Backspace**: Works from `:toolbar` mode. No change needed.

4. **Context menu**: Hidden on any keyboard shortcut — call `hook.contextMenu?.hide()` at the start of the handler.

**Test battery:**

| Test                            | What it verifies                                  |
|---------------------------------|---------------------------------------------------|
| Escape closes editor first      | When in `:editor`, Escape pushes `close_editor`   |
| Escape closes builder second    | When in `:builder`, Escape pushes `close_builder` |
| Escape deselects node third     | When in `:toolbar`, Escape pushes `deselect_node` |
| E opens editor for dialogue     | Pushes `open_screenplay`                          |
| E opens builder for condition   | Pushes `open_builder`                             |
| Delete still works from toolbar | Node deleted when toolbar visible                 |

> Run `mix test` and `mix credo --strict` before proceeding.

---

### Subtask 9: Gettext + cleanup

**Description:** Extract all new strings for i18n. Delete absorbed plan file. Clean up deprecated code.

**Modified files:**

| File                                      | Change                                 |
|-------------------------------------------|----------------------------------------|
| `priv/gettext/flows.pot` and translations | Extract new strings                    |
| `priv/gettext/en/LC_MESSAGES/flows.po`    | New entries                            |
| `priv/gettext/es/LC_MESSAGES/flows.po`    | New entries (translations added later) |

**Deleted files:**

| File                                              | Reason                              |
|---------------------------------------------------|-------------------------------------|
| `docs/plans/stress_test/02_CREATE_LINKED_FLOW.md` | Absorbed into this plan (Subtask 6) |

**New gettext strings:**
- "Back to canvas"
- "Create flow"
- "Create linked flow"
- "Edit"
- "Preview"
- "Settings"
- "Responses"
- "Locate target hub"
- "Locate referencing jumps"
- "View referencing flows"
- "%{count} assignments"
- "%{count} rules"
- "%{count} responses"
- "%{count} exits"
- "%{count} jumps"
- "%{count} refs"

> Run `mix gettext.extract --merge`, then `mix test` and `mix credo --strict`.

---

## Execution Order

```
Subtask 1: Context menu JS infrastructure        ─┐
Subtask 2: Floating toolbar JS infrastructure      ├─ JS infrastructure (parallel)
                                                   ─┘
         ↓
Subtask 3: Toolbar HEEx + per-type components     ─┐
Subtask 4: Builder panel (condition/instruction)    │
Subtask 5: Dialogue full editor (two-panel)         ├─ UI components (parallel)
Subtask 6: Create Linked Flow backend               │
                                                   ─┘
         ↓
Subtask 7: Remove sidebar + wire editing modes     ─ Integration
         ↓
Subtask 8: Keyboard handler updates                ─┐
Subtask 9: Gettext + cleanup                        ├─ Polish (parallel)
                                                   ─┘
```

---

## Files Summary

| File                                                                | Change           | Subtask       |
|---------------------------------------------------------------------|------------------|---------------|
| `assets/js/flow_canvas/context_menu.js`                             | **New**          | 1             |
| `assets/js/flow_canvas/context_menu_items.js`                       | **New**          | 1             |
| `assets/js/flow_canvas/floating_toolbar.js`                         | **New**          | 2             |
| `assets/js/hooks/flow_floating_toolbar.js`                          | **New**          | 2             |
| `assets/js/hooks/flow_canvas.js`                                    | Modified         | 1, 2          |
| `assets/js/flow_canvas/event_bindings.js`                           | Modified         | 1, 2          |
| `assets/js/hooks/index.js`                                          | Modified         | 2             |
| `lib/storyarn_web/live/flow_live/components/flow_toolbar.ex`        | **New**          | 3             |
| `lib/storyarn_web/live/flow_live/components/builder_panel.ex`       | **New**          | 4             |
| `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex`   | Modified (major) | 5             |
| `lib/storyarn/flows/flow_crud.ex`                                   | Modified         | 6             |
| `lib/storyarn/flows.ex`                                             | Modified         | 6             |
| `lib/storyarn_web/live/flow_live/show.ex`                           | Modified (major) | 3, 4, 5, 6, 7 |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Modified         | 7             |
| `lib/storyarn_web/live/flow_live/node_type_registry.ex`             | Modified         | 7             |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex`   | **Deleted**      | 7             |
| `assets/js/flow_canvas/handlers/keyboard_handler.js`                | Modified         | 8             |
| `docs/plans/stress_test/02_CREATE_LINKED_FLOW.md`                   | **Deleted**      | 9             |

---

**Next document:** [`04_EXPRESSION_SYSTEM.md`](04_EXPRESSION_SYSTEM.md) — Expression System: Code Editor + Visual Builder
