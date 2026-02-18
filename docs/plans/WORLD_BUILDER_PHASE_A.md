# World Builder — Phase A: Core UX Rewrite

> **Goal:** Replace the confusing 4-mode toolbar with a FigJam-style Edit/View paradigm + bottom dock.
> Make the world builder intuitive and useful from the first interaction.
>
> **Depends on:** Phases 1-3 complete (backend + canvas working). Phase 3 fixes applied (IDOR, bugs, tests).
>
> **Baseline:** 1808 tests passing, 0 credo issues.
>
> **Current:** 1824 tests passing, Tasks 1–7 complete.

---

## Design Vision

**Before (current):** 4 cryptic modes (pan/pin/zone/connect), double-click to close polygon, no context menus, no annotations, no sheet integration.

**After (Phase A):** 2 clear modes (Edit/View), bottom dock with tool palette, ghost preview for shapes, click-to-place, right-click context menus, pins from sheets with avatars, annotations.

### Interaction Model

```
EDIT MODE:
┌─────────────────────────────────────────────────────────────────────────┐
│ ← Maps   World Map                                     #maps.world    │
├────────────────────────────────────────────────────────┬────────────────┤
│                                                        │ Properties     │
│   [Canvas with background image, zones, pins, etc.]    │ (right panel)  │
│                                                        │                │
│                                                        │                │
│                                                        │                │
│                                                        │                │
├────────────────────────────────────────────────────────┤                │
│ [Layers bar]                                           │                │
│                                                        │                │
│ ┌──────────────────────────────────────────────────┐   │                │
│ │  🖱  ✋  ▭ ▽ ○ ⬠  📌  📝  ⟋   │  ← Dock        │                │
│ └──────────────────────────────────────────────────┘   │                │
└────────────────────────────────────────────────────────┴────────────────┘

Dock tools (left to right):
  🖱 Select (default) — click to select, drag to move elements
  ✋ Pan — drag canvas to pan
  ▭ Rectangle — click to place rectangle zone
  ▽ Triangle — click to place triangle zone
  ○ Circle — click to place circle zone (approximated as polygon)
  ⬠ Freeform — click vertices, auto-close on first vertex click
  📌 Pin — dropdown: Free pin | From Sheet (with avatar)
  📝 Annotation — click to place text note
  ⟋ Connector — click pin A → click pin B to draw line

Right-click context menus on every element.
```

---

## Task 1: Replace Toolbar with Edit/View Mode Toggle ✅

### What changes
Remove the 4-mode toolbar (pan/pin/zone/connect). Replace with a single Edit/View toggle. In Edit mode, the bottom dock controls the active tool. In View mode, the canvas is read-only (pan + zoom + hover tooltips only).

### Files to modify

**`lib/storyarn_web/live/map_live/show.ex`**
- Replace `@mode` atom (`:pan | :pin | :zone | :connect`) with `@edit_mode` boolean + `@active_tool` atom (`:select | :pan | :rectangle | :triangle | :circle | :freeform | :pin | :annotation | :connector`)
- Default: `@edit_mode = can_edit`, `@active_tool = :select`
- Remove `set_mode` event handler. Add `set_tool` event handler and `toggle_edit_mode` handler.
- `set_tool` pushes `tool_changed` event to JS hook with `%{tool: tool_name}`.
- `toggle_edit_mode` flips `@edit_mode` and pushes `edit_mode_changed` to JS.

**`lib/storyarn_web/live/map_live/show.ex` (template)**
- Remove the toolbar div (`.absolute.top-3.left-3`).
- Add Edit/View toggle button in the header (right side).
- When `@edit_mode`, render the bottom dock component.

**`assets/js/hooks/map_canvas.js`**
- Replace `mode_changed` handler with `tool_changed` and `edit_mode_changed` handlers.
- `tool_changed`: store `hook.currentTool`, update cursor, cancel any in-progress drawing.
- `edit_mode_changed`: toggle `hook.editMode`, when entering View mode cancel all drawing and switch to pan.

**`assets/js/map_canvas/handlers/pin_handler.js`**
- Replace `hook.currentMode === "pin"` checks with `hook.currentTool === "pin"`.

**`assets/js/map_canvas/handlers/zone_handler.js`**
- Replace `hook.currentMode === "zone"` checks with freeform tool check.

**`assets/js/map_canvas/handlers/connection_handler.js`**
- Replace `hook.currentMode === "connect"` checks with `hook.currentTool === "connector"`.

### Tests

**`test/storyarn_web/live/map_live/show_test.exs`**
- `set_tool` event updates active tool
- `toggle_edit_mode` flips edit mode
- Viewer cannot toggle to edit mode
- Dock not rendered for viewer
- Edit/View toggle renders in header

### Verification
```bash
mix test test/storyarn_web/live/map_live/show_test.exs
mix credo
```

---

## Task 2: Bottom Dock Component ✅

### What changes
Create a bottom dock component (`dock.ex`) that renders tool buttons. Each button highlights when active. Tools with sub-options (shapes, pins) show a dropdown/popover on click.

### Files to create

**`lib/storyarn_web/live/map_live/components/dock.ex`**
- Function component `dock/1` that receives:
  - `active_tool` — current tool atom
  - `can_edit` — boolean
- Renders a horizontal bar at the bottom-center of the canvas area (absolute positioned, z-1000).
- Tool buttons: Select, Pan, Rectangle, Triangle, Circle, Freeform, Pin, Annotation, Connector.
- Each button: `phx-click="set_tool" phx-value-tool="rectangle"`.
- Active tool gets `btn-primary` class.
- Grouped visually: [Select, Pan] | [Rect, Triangle, Circle, Freeform] | [Pin, Annotation] | [Connector]
- Separator dividers between groups (thin border-l).
- Icons: Select → `mouse-pointer-2`, Pan → `hand`, Rectangle → `square`, Triangle → `triangle`, Circle → `circle`, Freeform → `pentagon`, Pin → `map-pin`, Annotation → `sticky-note`, Connector → `cable`.

### Files to modify

**`lib/storyarn_web/live/map_live/show.ex` (template)**
- Import dock component.
- Render `<.dock>` inside the canvas area (bottom-center), only when `@edit_mode`.
- Wrap in a container with `absolute bottom-4 left-1/2 -translate-x-1/2 z-[1000]`.

### Tests

**`test/storyarn_web/live/map_live/show_test.exs`**
- Dock renders for editor in edit mode
- Dock does not render for viewer
- All tool buttons present in dock
- Clicking a tool button updates active tool
- Active tool button has primary styling

### Verification
```bash
mix test test/storyarn_web/live/map_live/show_test.exs
mix credo
```

---

## Task 3: Shape Preset Zones — Rectangle, Triangle, Circle ✅

### What changes
When the user selects a shape tool (rectangle/triangle/circle) and clicks on the canvas, a zone is created at that position with predefined vertices. A ghost preview follows the cursor before placement.

### Shape Definitions (percentage-based, centered on click point)

**Rectangle** (20×15 units):
```js
[{x: cx-10, y: cy-7.5}, {x: cx+10, y: cy-7.5}, {x: cx+10, y: cy+7.5}, {x: cx-10, y: cy+7.5}]
```

**Triangle** (20×17 units, equilateral-ish):
```js
[{x: cx, y: cy-8.5}, {x: cx+10, y: cy+8.5}, {x: cx-10, y: cy+8.5}]
```

**Circle** (approximated as 16-sided polygon, radius 10 units):
```js
Array.from({length: 16}, (_, i) => {
  const angle = (i / 16) * 2 * Math.PI;
  return { x: cx + 10 * Math.cos(angle), y: cy + 10 * Math.sin(angle) };
})
```

All vertices clamped to 0-100 range.

### Files to create

**`assets/js/map_canvas/shape_presets.js`**
- Export functions: `rectangleVertices(cx, cy)`, `triangleVertices(cx, cy)`, `circleVertices(cx, cy, sides=16)`
- Each returns an array of `{x, y}` in percentage coordinates.
- All values clamped to [0, 100].

### Files to modify

**`assets/js/map_canvas/handlers/zone_handler.js`**
- Import shape presets.
- In the map click handler, if tool is `rectangle/triangle/circle`:
  - Convert click latlng to percent.
  - Generate vertices from preset.
  - Push `create_zone` event with vertices + default name.
  - Do NOT enter drawing mode — single click creates the zone.
- Keep freeform behavior (click vertices) only for `freeform` tool.

**`assets/js/hooks/map_canvas.js`**
- Pass `hook.currentTool` to zone handler so it knows which shape preset to use.

### Ghost Preview (cursor feedback)

**`assets/js/map_canvas/handlers/zone_handler.js`**
- When a shape tool is active, on `mousemove`:
  - Show a semi-transparent preview polygon (the shape centered on cursor).
  - Use `L.polygon` with dashed border, low opacity, `interactive: false`.
- On mouse leave canvas, remove preview.
- On click, remove preview and create the zone.

### Tests

**`test/storyarn_web/live/map_live/show_test.exs`**
- `create_zone` with rectangle preset vertices (4 vertices) creates zone
- `create_zone` with triangle preset vertices (3 vertices) creates zone
- `create_zone` with circle preset vertices (16 vertices) creates zone
- All zones have valid coordinates (0-100 range)

### Verification
```bash
mix test test/storyarn_web/live/map_live/show_test.exs
mix credo
```

---

## Task 4: Freeform Zone Drawing — Auto-Close on First Vertex ✅

### What changes
Replace the confusing double-click-to-close with auto-close: when the user clicks near the first vertex (within a threshold), the polygon closes automatically. Visual feedback shows the close target.

### Files to modify

**`assets/js/map_canvas/handlers/zone_handler.js`**
- Remove the `dblclick` handler for closing zones.
- In the click handler (freeform tool):
  - If `drawingVertices.length >= 3` and click is within 15px of first vertex marker → call `finishDrawing()`.
  - First vertex marker gets a special style (larger, pulsing, different color) to indicate "click here to close".
  - On hover near first vertex (mousemove within threshold), change cursor to crosshair or show a "close" indicator.
- Add Escape key handler to cancel drawing (already exists, keep it).

**`assets/css/app.css`**
- Add `.map-zone-close-target` class for the first vertex indicator:
  ```css
  .map-zone-close-target {
    animation: pulse 1.5s ease-in-out infinite;
  }
  @keyframes pulse {
    0%, 100% { transform: scale(1); opacity: 1; }
    50% { transform: scale(1.3); opacity: 0.7; }
  }
  ```

### Behavior
1. User selects Freeform tool in dock.
2. Clicks to place vertices (preview polygon shows in real-time).
3. After 3+ vertices, first vertex marker pulses to indicate "click to close".
4. User clicks near first vertex → polygon closes → `create_zone` event pushed.
5. Escape cancels drawing at any point.
6. Switching tool cancels drawing.

### Tests

**`test/storyarn_web/live/map_live/show_test.exs`**
- Existing `create_zone` tests still pass (backend doesn't change).
- Existing zone validation tests still pass.

### Verification
```bash
mix test test/storyarn_web/live/map_live/show_test.exs
mix credo
```

---

## Task 5: Zone Drag & Drop (Move Entire Zone) ✅

### What changes
In Select mode, clicking a zone selects it. Dragging a selected zone moves the entire polygon (all vertices shift by the same delta). Currently zones can only be reshaped via vertex editing — this adds whole-zone movement.

### Files to modify

**`assets/js/map_canvas/handlers/zone_handler.js`**
- In `addZoneToMap()`, when tool is `:select`:
  - On `mousedown` on a selected polygon: start drag.
  - Store initial mouse position and initial vertices.
  - On `mousemove` while dragging: compute delta, update polygon latlngs in real-time.
  - On `mouseup`: convert new vertices to percentages, push `update_zone_vertices` event.
- Prevent drag when in freeform/shape tool mode (those tools handle clicks differently).
- Set cursor to `grab` on hover over selected zone, `grabbing` while dragging.

**`assets/js/map_canvas/zone_renderer.js`**
- No changes needed — `updateZoneVertices` already handles new vertex arrays.

### Important: Clamp vertices
When dragging, all shifted vertices must stay within 0-100 range. If any vertex would go out of bounds, clamp the delta.

### Tests

**`test/storyarn_web/live/map_live/show_test.exs`**
- `update_zone_vertices` with shifted vertices (simulating drag) updates correctly
- Vertices remain within 0-100 range after drag

### Verification
```bash
mix test test/storyarn_web/live/map_live/show_test.exs
mix credo
```

---

## Task 6: Right-Click Context Menus ✅

### What changes
Add right-click context menus to all canvas elements (zones, pins, connections) and to empty canvas space. Replaces the need for users to "know" hidden interactions.

### Files to create

**`assets/js/map_canvas/context_menu.js`**
- Factory function `createContextMenu(hook)` that manages a single context menu DOM element.
- API: `show(x, y, items)`, `hide()`.
- `items` is an array of `{ label, icon, action, danger? }`.
- `action` is a callback function.
- Renders as a dropdown menu (daisyUI `menu` class) positioned at cursor coordinates.
- Auto-hides on click outside, Escape, or scroll.
- Z-index above everything (9999).

### Context Menu Items

**On empty canvas (right-click on background):**
- "Add Pin Here" → creates pin at click position
- "Add Annotation Here" → creates annotation at click position (Phase A Task 8)

**On pin:**
- "Edit Properties" → selects pin (opens properties panel)
- "Connect To..." → enters connector mode with this pin as source
- "Delete" (danger) → triggers delete confirm flow

**On zone:**
- "Edit Properties" → selects zone
- "Edit Vertices" → shows vertex handles (vertex editor)
- "Duplicate" → creates copy offset by 5%
- "Delete" (danger) → triggers delete confirm flow

**On connection:**
- "Edit Properties" → selects connection
- "Delete" (danger) → triggers delete confirm flow

### Files to modify

**`assets/js/map_canvas/handlers/pin_handler.js`**
- Add `contextmenu` event on each pin marker → `hook.contextMenu.show(...)` with pin-specific items.

**`assets/js/map_canvas/handlers/zone_handler.js`**
- Add `contextmenu` event on each zone polygon → show zone-specific items.
- "Edit Vertices" item → calls `vertexEditor.show(polygon)`.
- "Duplicate" item → pushes `duplicate_zone` event.

**`assets/js/map_canvas/handlers/connection_handler.js`**
- Add `contextmenu` event on each connection line → show connection-specific items.

**`assets/js/hooks/map_canvas.js`**
- Create context menu instance and pass to handlers.
- Add `contextmenu` on canvas background → show canvas-level items.
- Prevent browser default context menu on the canvas container.

**`lib/storyarn_web/live/map_live/show.ex`**
- Add `handle_event("duplicate_zone", ...)` → copies zone with shifted vertices (+5% offset).

**`assets/css/app.css`**
- Style `.map-context-menu` (if needed beyond daisyUI defaults).

### Tests

**`test/storyarn_web/live/map_live/show_test.exs`**
- `duplicate_zone` creates a new zone with shifted vertices
- `duplicate_zone` rejected for viewer
- Original zone unchanged after duplication

**`test/storyarn/maps_test.exs`**
- No context changes needed — uses existing CRUD functions.

### Verification
```bash
mix test test/storyarn_web/live/map_live/show_test.exs test/storyarn/maps_test.exs
mix credo
```

---

## Task 7: Pins from Sheets (Avatar Integration) ✅

### What changes
The Pin tool in the dock has a dropdown with two options:
1. **Free Pin** — creates a generic pin (current behavior)
2. **From Sheet** — opens a sheet picker; selected sheet becomes a pin with its avatar as the marker image

### Schema Change

**`lib/storyarn/maps/map_pin.ex`** — Add `sheet_id` field:
- New optional field: `sheet_id` (references sheets table, on_delete: nilify_all).
- When `sheet_id` is set, the pin inherits the sheet's avatar for its visual.

**Migration** — `priv/repo/migrations/XXXXXX_add_sheet_id_to_map_pins.exs`:
```elixir
alter table(:map_pins) do
  add :sheet_id, references(:sheets, on_delete: :nilify_all)
end
create index(:map_pins, [:sheet_id])
```

### Files to modify

**`lib/storyarn/maps/map_pin.ex`**
- Add `belongs_to :sheet, Storyarn.Sheets.Sheet`
- Add `:sheet_id` to changeset cast.

**`lib/storyarn_web/live/map_live/show.ex`**
- Add `handle_event("create_pin_from_sheet", %{"sheet_id" => id, "position_x" => x, "position_y" => y}, socket)`.
- Loads sheet (with avatar_asset), creates pin with:
  - `label` = sheet.name
  - `pin_type` = "character" (or inferred from sheet type)
  - `sheet_id` = sheet.id
  - `target_type` = "sheet", `target_id` = sheet.id
- Serialization: include `sheet_id`, `avatar_url` (from sheet's avatar_asset.url) in `serialize_pin/1`.
- Pass `project_sheets` (with avatar preloaded) to dock for the sheet picker.

**`lib/storyarn_web/live/map_live/components/dock.ex`**
- Pin tool button: on click, show dropdown with "Free Pin" and "From Sheet".
- "From Sheet" opens a popover/modal with a searchable list of project sheets.
- Each sheet row shows: avatar thumbnail + name + shortcut.
- Clicking a sheet enters "place pin from sheet" mode → next canvas click creates the pin.

**`assets/js/map_canvas/pin_renderer.js`**
- If pin has `avatar_url`, render the marker as a circular avatar image instead of a Lucide icon.
- Use `L.divIcon` with an `<img>` element for avatar, or Lucide icon as fallback.
- If `sheet_id` but no `avatar_url`, render initials (first 2 chars of label) in a colored circle.

**`assets/js/map_canvas/handlers/pin_handler.js`**
- Handle `create_pin_from_sheet` tool mode: when canvas clicked, push `create_pin_from_sheet` event with sheet_id + coordinates.

### Tests

**`test/storyarn/maps_test.exs`**
- `create_pin` with `sheet_id` stores the reference
- Pin with `sheet_id` preloads sheet and avatar_asset

**`test/storyarn_web/live/map_live/show_test.exs`**
- `create_pin_from_sheet` creates pin linked to sheet
- Pin serialization includes `avatar_url` when sheet has avatar
- Pin serialization handles sheet without avatar (nil avatar_url)
- `create_pin_from_sheet` rejected for viewer

### Verification
```bash
mix test test/storyarn/maps_test.exs test/storyarn_web/live/map_live/show_test.exs
mix credo
```

---

## Task 8: Annotations (Text Notes on Canvas)

### What changes
Add a new element type: annotations. Simple text labels placed directly on the canvas. They are persistent, belong to a layer, and can be moved/edited/deleted.

### Schema

**Migration** — `priv/repo/migrations/XXXXXX_create_map_annotations.exs`:
```elixir
create table(:map_annotations) do
  add :map_id, references(:maps, on_delete: :delete_all), null: false
  add :layer_id, references(:map_layers, on_delete: :nilify_all)
  add :text, :text, null: false
  add :position_x, :float, null: false  # percentage 0-100
  add :position_y, :float, null: false
  add :font_size, :string, default: "md"  # sm | md | lg
  add :color, :string  # hex color
  add :position, :integer, default: 0
  timestamps(type: :utc_datetime)
end
create index(:map_annotations, [:map_id, :layer_id])
```

### Files to create

**`lib/storyarn/maps/map_annotation.ex`** — Schema:
- Fields: `text`, `position_x`, `position_y`, `font_size`, `color`, `position`
- Associations: `belongs_to :map`, `belongs_to :layer`
- Validation: text required (1-500 chars), position 0-100, font_size in ~w(sm md lg)

**`lib/storyarn/maps/annotation_crud.ex`** — CRUD:
- `list_annotations/1` (by map_id, ordered by position)
- `create_annotation/2`
- `update_annotation/2`
- `move_annotation/3` (position_x/y only, drag optimization)
- `delete_annotation/1`

**`assets/js/map_canvas/annotation_renderer.js`**:
- `createAnnotationMarker(annotation, w, h, opts)` → `L.marker` with `L.divIcon` containing a text element.
- Editable on double-click (inline contenteditable).
- Draggable in edit mode.

**`assets/js/map_canvas/handlers/annotation_handler.js`**:
- Similar pattern to pin_handler: manages annotation markers, wires events.
- Click to place (Annotation tool active), drag to move, double-click to edit text inline.
- Server events: `annotation_created`, `annotation_updated`, `annotation_deleted`.

### Files to modify

**`lib/storyarn/maps.ex`** — Add defdelegate for annotation CRUD.

**`lib/storyarn/maps/map.ex`** — Add `has_many :annotations, MapAnnotation`.

**`lib/storyarn_web/live/map_live/show.ex`**:
- Mount: load annotations.
- Serialize annotations in `build_map_data`.
- Add handlers: `create_annotation`, `update_annotation`, `move_annotation`, `delete_annotation`.
- Add annotation to `select_element` types.

**`lib/storyarn_web/live/map_live/components/properties_panel.ex`**:
- Add `annotation_properties/1` component (text, font_size, color, layer, delete).

**`assets/js/hooks/map_canvas.js`**:
- Init annotation handler.
- Wire annotation events.

### Tests

**`test/storyarn/maps_test.exs`**
- Annotation CRUD (create, update, move, delete)
- Validation (text required, position 0-100, font_size enum)
- Layer association

**`test/storyarn_web/live/map_live/show_test.exs`**
- `create_annotation` creates annotation
- `create_annotation` rejected for viewer
- `update_annotation` updates text
- `delete_annotation` removes annotation
- Annotation serialized in map_data JSON

### Verification
```bash
mix test test/storyarn/maps_test.exs test/storyarn_web/live/map_live/show_test.exs
mix credo
```

---

## Task 9: Layer Delete & Rename UI

### What changes
Add missing UI for layer management: delete button (with confirmation) and inline rename.

### Files to modify

**`lib/storyarn_web/live/map_live/show.ex` (template — layer bar)**
- Each layer in the bar gets a right-click context menu or a small kebab menu (`...`) with:
  - "Rename" → inline text input
  - "Delete" → confirm modal (existing `delete-layer-confirm` pattern)
- Rename: `handle_event("rename_layer", %{"id" => id, "name" => name})` → `Maps.update_layer(layer, %{name: name})`.
- Delete: Use existing `delete_layer` handler (already implemented).

**`lib/storyarn_web/live/map_live/show.ex` (handlers)**
- Add `handle_event("rename_layer", ...)`.

### Alternative: Inline edit
- Double-click layer name in bar → contenteditable → on blur push rename event.
- Simpler than a menu, but needs the kebab menu for delete.

### Design Decision
Add a small dropdown triggered by right-click or kebab icon on each layer item:
- "Rename" → makes the name editable inline
- "Delete" → shows confirm modal (disabled if last layer)

### Tests

**`test/storyarn_web/live/map_live/show_test.exs`**
- `rename_layer` updates layer name
- `rename_layer` rejected for viewer
- Delete layer button triggers existing delete flow

### Verification
```bash
mix test test/storyarn_web/live/map_live/show_test.exs
mix credo
```

---

## Task Dependency Graph

```
Task 1 (Edit/View Mode) ✅
Task 2 (Dock Component) ✅
Task 3 (Shape Presets) ✅
Task 4 (Freeform Auto-Close) ✅
Task 5 (Zone Drag) ✅
Task 6 (Context Menus) ✅
Task 7 (Pins from Sheets) ✅
Task 8 (Annotations) ← Task 2 ✅
Task 9 (Layer Delete/Rename) ← no dependencies
```

**Recommended order:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9

## Workflow per Task

1. Read task description carefully
2. Implement the task
3. Run `mix credo` — fix any issues
4. Run `mix test` — all tests pass
5. Ask user for review before moving to next task
