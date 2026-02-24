# World Builder — Phase B: Polish & Connections

> **Goal:** Improve connection UX, add search/filter, legend, image pins, and path drawing.
>
> **Depends on:** Phase A complete (dock, context menus, shape presets, annotations, pins from sheets).
>
> **Baseline:** Phase A tests passing, 0 credo issues.

---

## Task 1: Connections Redesign — Visual Feedback

### Problem
Current connection drawing has no feedback. The user enters connect mode, clicks a pin, and nothing visually indicates that a connection is being drawn until the second pin is clicked.

### What changes
Redesign connection drawing to be intuitive:
1. User selects Connector tool in dock.
2. Hover over any pin → pin highlights with a "connectable" indicator (ring glow).
3. Click first pin → pin gets "source" highlight + a dashed line follows the cursor from pin to mouse.
4. Hover over another pin → that pin highlights as "target".
5. Click second pin → connection created, both highlights removed, preview line removed.
6. Click empty canvas or Escape → cancel connection.
7. Click same pin → cancel (no self-connect).

### Files to modify

**`assets/js/scene_canvas/handlers/connection_handler.js`**
- Add `mousemove` handler: when first pin selected, draw a temporary `L.polyline` from source pin to cursor position (dashed, semi-transparent).
- Add pin hover detection: when connector tool active, add visual indicator to pins on `mouseover` (CSS class `map-pin-connectable`).
- On first pin click: add `map-pin-source` class to source pin marker.
- On second pin click: remove all temporary styles, push `create_connection`.
- On Escape/canvas click: cancel and cleanup.

**`assets/js/scene_canvas/pin_renderer.js`**
- No changes — CSS handles the visual states.

**`assets/css/app.css`**
- Add `.map-pin-connectable` — subtle ring on hover when connector tool active.
- Add `.map-pin-source` — prominent highlight (primary color glow) on the source pin.
- Add `.map-pin-target` — highlight on the target pin candidate.

### Tests

**`test/storyarn_web/live/scene_live/show_test.exs`**
- Existing connection creation tests still pass (backend unchanged).
- Connection creation rejected for viewer (existing test).

### Verification
```bash
mix test test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task 2: Path Drawing — Curved Connections

### Problem
Current connections are straight lines. Real-world routes (roads, rivers) are curved.

### What changes
Add a `waypoints` field to connections. Waypoints are intermediate points that the connection line passes through, creating curved paths using Leaflet's polyline with interpolated points.

### Schema Change

**Migration** — `priv/repo/migrations/XXXXXX_add_waypoints_to_connections.exs`:
```elixir
alter table(:map_connections) do
  add :waypoints, :jsonb, default: "[]"  # [{x, y}, ...] percentage-based
end
```

### Files to modify

**`lib/storyarn/maps/map_connection.ex`**
- Add `field :waypoints, {:array, :map}, default: []`.
- Validation: each waypoint has x/y in 0-100 range.

**`lib/storyarn/maps/connection_crud.ex`**
- `update_connection_waypoints/2` — optimized changeset for drag.

**`assets/js/scene_canvas/connection_renderer.js`**
- `createConnectionLine`: if `conn.waypoints` is non-empty, build a polyline through [from_pin, ...waypoints, to_pin].
- Use smooth interpolation (catmull-rom or simple bezier approximation) for nicer curves. Alternatively, use `L.curve` plugin or just polyline through waypoints.

**`assets/js/scene_canvas/handlers/connection_handler.js`**
- When a connection is selected, show draggable waypoint handles (similar to vertex editor for zones).
- Double-click on a connection line → add a waypoint at that position.
- Drag waypoint → update in real-time → push `update_connection_waypoints` on dragend.
- Right-click waypoint → "Remove Waypoint".

**`lib/storyarn_web/live/scene_live/show.ex`**
- Add `handle_event("update_connection_waypoints", ...)`.
- Include `waypoints` in `serialize_connection/1`.

**`lib/storyarn_web/live/scene_live/components/properties_panel.ex`**
- Connection properties: show waypoint count (read-only info).
- "Clear Waypoints" button to reset to straight line.

### Tests

**`test/storyarn/scenes_test.exs`**
- `create_connection` with waypoints stores them.
- `update_connection_waypoints` updates waypoints.
- Waypoint validation (coordinates 0-100).

**`test/storyarn_web/live/scene_live/show_test.exs`**
- `update_connection_waypoints` event updates waypoints.
- Connection serialization includes waypoints.
- Viewer cannot update waypoints.

### Verification
```bash
mix test test/storyarn/scenes_test.exs test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task 3: Search & Filter

### What changes
Add a search bar and type filter above the canvas to find elements on the map. Searching highlights matching elements and optionally centers the view on them.

### Files to modify

**`lib/storyarn_web/live/scene_live/show.ex` (template)**
- Add a search input in the header area (or as a floating bar):
  - Text input with `phx-change="search_elements"` (debounced).
  - Type filter buttons/dropdown: All | Pins | Zones | Annotations | Connections.
- Add `@search_query` and `@search_filter` assigns.

**`lib/storyarn_web/live/scene_live/show.ex` (handlers)**
- `handle_event("search_elements", %{"query" => q}, socket)`:
  - Filter `@pins`, `@zones`, `@annotations` by name/label/text containing query.
  - Push `highlight_elements` event to JS with list of matching IDs + types.
- `handle_event("clear_search", ...)` → clears search and highlights.
- `handle_event("focus_element", %{"type" => type, "id" => id})` → pushes `focus_element` to JS.

**`assets/js/hooks/scene_canvas.js`**
- Handle `highlight_elements` → dim non-matching elements (reduce opacity), highlight matches.
- Handle `focus_element` → pan/zoom to center on element, flash highlight.

**`assets/js/scene_canvas/handlers/pin_handler.js`**
- Add `setHighlighted(pinId, highlighted)` method to toggle visual state.
- `focusPin(pinId)` → fly to pin location.

**`assets/js/scene_canvas/handlers/zone_handler.js`**
- Add `setHighlighted(zoneId, highlighted)` method.
- `focusZone(zoneId)` → fit bounds to zone vertices.

### Tests

**`test/storyarn_web/live/scene_live/show_test.exs`**
- `search_elements` returns matching pins by label
- `search_elements` returns matching zones by name
- `search_elements` with empty query clears highlights
- `clear_search` resets search state

### Verification
```bash
mix test test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task 4: Auto-Generated Legend

### What changes
Add a collapsible legend panel that shows all pin types, zone colors, and connection styles used on the current map. Auto-generated from the map's elements — no manual configuration.

### Files to create

**`lib/storyarn_web/live/scene_live/components/legend.ex`**
- Function component `legend/1` receiving `pins`, `zones`, `connections`.
- Groups pins by `pin_type` + `color` → shows icon + color swatch + count.
- Groups zones by `fill_color` → shows color swatch + count.
- Groups connections by `line_style` + `color` → shows line preview + count.
- Clicking a legend entry highlights those elements on the canvas (optional — Phase C scope).

### Files to modify

**`lib/storyarn_web/live/scene_live/show.ex` (template)**
- Add legend component in the bottom-right corner (floating, collapsible).
- Toggle with a small icon button.
- Pass `@pins`, `@zones`, `@connections` to legend.

### Tests

**`test/storyarn_web/live/scene_live/show_test.exs`**
- Legend renders when map has pins
- Legend shows correct pin type groupings
- Legend shows correct zone color groupings
- Legend collapses/expands

### Verification
```bash
mix test test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task 5: Image Pins (Custom Icon Images)

### What changes
Allow pins to use custom uploaded images as their icon, beyond Lucide icons and sheet avatars. The user can upload a small image (castle, mountain, skull) and assign it to a pin type.

### Schema Change

**Migration** — `priv/repo/migrations/XXXXXX_add_icon_asset_to_pins.exs`:
```elixir
alter table(:map_pins) do
  add :icon_asset_id, references(:assets, on_delete: :nilify_all)
end
```

### Files to modify

**`lib/storyarn/maps/map_pin.ex`**
- Add `belongs_to :icon_asset, Storyarn.Assets.Asset`.
- Add `:icon_asset_id` to changeset cast.

**`lib/storyarn_web/live/scene_live/components/properties_panel.ex`**
- In pin properties: add "Custom Icon" section.
- If `icon_asset_id` is set, show the image with a "Remove" button.
- "Upload Icon" button → uses `AssetUpload` component (accept images only, small max size ~512KB).

**`lib/storyarn_web/live/scene_live/show.ex`**
- Add `handle_info({:pin_icon_uploaded, asset}, socket)` → updates selected pin's `icon_asset_id`.
- Include `icon_asset_url` in `serialize_pin/1` (from icon_asset.url).

**`assets/js/scene_canvas/pin_renderer.js`**
- Rendering priority: `icon_asset_url` > `avatar_url` (from sheet) > Lucide icon.
- If `icon_asset_url`: render as `<img>` inside divIcon, sized to pin's `size` setting.

### Tests

**`test/storyarn/scenes_test.exs`**
- `create_pin` with `icon_asset_id` stores reference.
- `update_pin` to set/clear `icon_asset_id`.

**`test/storyarn_web/live/scene_live/show_test.exs`**
- Pin serialization includes `icon_asset_url` when set.
- Pin serialization handles nil `icon_asset_id`.

### Verification
```bash
mix test test/storyarn/scenes_test.exs test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task Dependency Graph

```
Task 1 (Connection Feedback) ← no dependencies
Task 2 (Path Drawing) ← Task 1
Task 3 (Search & Filter) ← no dependencies
Task 4 (Legend) ← no dependencies
Task 5 (Image Pins) ← no dependencies
```

**Recommended order:** 1 → 2 → 3 → 4 → 5

## Workflow per Task

1. Read task description carefully
2. Implement the task
3. Run `mix credo` — fix any issues
4. Run `mix test` — all tests pass
5. Ask user for review before moving to next task
