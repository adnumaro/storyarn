# World Builder — Phase C: Advanced Features

> **Goal:** Add advanced world-building tools: Fog of War, mini-map, ruler/distance, and map export.
>
> **Depends on:** Phase B complete (connections redesign, search, legend, image pins).
>
> **Baseline:** Phase B tests passing, 0 credo issues.

---

## Task 1: Fog of War / Progressive Reveal

### Overview
Fog of War allows map creators to hide portions of the map. Viewers see only revealed areas — the rest is covered by a dark overlay. Creators define "reveal zones" (polygonal regions) that can be toggled on/off, either manually or via variable triggers (layer system).

### Design
- Fog of War is a **layer-level feature**: each layer can have `fog_enabled: true`.
- When fog is enabled, all zones on that layer act as "reveal windows" — areas inside zones are visible, everything else is darkened.
- When fog is disabled (default), the layer behaves normally.
- This leverages the existing layer + zone architecture without new element types.

### Schema Change

**Migration** — `priv/repo/migrations/XXXXXX_add_fog_to_layers.exs`:
```elixir
alter table(:map_layers) do
  add :fog_enabled, :boolean, default: false, null: false
  add :fog_color, :string, default: "#000000"
  add :fog_opacity, :float, default: 0.85
end
```

### Files to modify

**`lib/storyarn/maps/map_layer.ex`**
- Add fields: `fog_enabled` (boolean), `fog_color` (string), `fog_opacity` (float 0-1).
- Validation: fog_opacity 0-1.

**`lib/storyarn_web/live/scene_live/show.ex`**
- Include fog fields in `serialize_layer/1`.
- Add `handle_event("update_layer_fog", %{"id" => id, "fog_enabled" => val})`.

**`assets/js/scene_canvas/handlers/layer_handler.js`**
- When rendering layers, if a layer has `fog_enabled: true`:
  - Create a full-canvas dark overlay (`L.rectangle` with fog_color and fog_opacity).
  - For each zone in the fog layer, cut out the zone's polygon from the overlay.
  - Use SVG clip-path or Leaflet's `L.Polygon` with a "hole" pattern: create a large rectangle with zone polygons as interior rings (holes).

**Implementation approach — Polygon with holes:**
```js
// Create a polygon that covers the entire canvas
// with "holes" where reveal zones are
const canvasBounds = [
  [0, 0], [0, width], [-height, width], [-height, 0]  // outer ring
];
const holes = fogZones.map(zone => zone.getLatLngs()[0]);  // inner rings

const fogOverlay = L.polygon([canvasBounds, ...holes], {
  color: 'transparent',
  fillColor: fogColor,
  fillOpacity: fogOpacity,
  interactive: false,
});
```

**`lib/storyarn_web/live/scene_live/components/properties_panel.ex`**
- In layer properties (if we add a layer properties section) or in the layer bar context menu:
  - "Enable Fog of War" toggle.
  - Fog color picker.
  - Fog opacity slider.

### Integration with Variable Triggers
Fog layers can use the existing `trigger_sheet`, `trigger_variable`, `trigger_value` fields. When the trigger condition is met, the fog layer activates — revealing the areas defined by its zones. This enables narrative-driven progressive reveal:

```
Layer: "Chapter 2 Reveal"
  fog_enabled: true
  trigger_sheet: "story.progress"
  trigger_variable: "chapter"
  trigger_value: "2"
  → When story.progress.chapter == "2", this fog layer activates and reveals its zones
```

### Tests

**`test/storyarn/scenes_test.exs`**
- `create_layer` with `fog_enabled: true` stores the flag.
- `update_layer` fog fields validation (opacity 0-1).

**`test/storyarn_web/live/scene_live/show_test.exs`**
- `update_layer_fog` enables fog on a layer.
- `update_layer_fog` rejected for viewer.
- Layer serialization includes fog fields.

### Verification
```bash
mix test test/storyarn/scenes_test.exs test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task 2: Mini-Map Navigation

### Overview
A small overview map in the corner that shows the full map with a viewport indicator. Clicking on the mini-map pans the main view. Essential for large maps where the user can get lost.

### Implementation
Use Leaflet's `L.Control` to create a custom mini-map control. The mini-map is a second, smaller `L.map` instance that mirrors the main map's layers but at a fixed zoom level showing the full extent.

### Files to create

**`assets/js/scene_canvas/minimap.js`**
- `createMinimap(hook)` factory function.
- Creates a secondary Leaflet map in a small container (200×150px).
- Positioned bottom-right (above legend if present).
- Shows the same background image at full extent.
- Draws a red rectangle representing the main map's current viewport.
- On main map `moveend`/`zoomend` → updates viewport rectangle.
- On minimap click → pans main map to that location.
- Collapsible with a toggle button.

### Files to modify

**`assets/js/hooks/scene_canvas.js`**
- Import and initialize minimap after map setup.
- Pass background image URL to minimap.
- Wire main map events to minimap updates.

**`assets/css/app.css`**
- `.map-minimap` container styling (border, shadow, background).
- `.map-minimap-viewport` rectangle styling (red outline, semi-transparent fill).
- `.map-minimap-toggle` button styling.

### Tests

**`test/storyarn_web/live/scene_live/show_test.exs`**
- No backend tests needed — minimap is purely client-side.
- Verify map_data still includes background_url for minimap to use.

### Verification
```bash
mix test test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task 3: Ruler / Distance Measurement

### Overview
A measurement tool that lets users click two points on the map and see the distance between them. Useful for travel time calculations in RPGs and spatial planning.

### Design
- Ruler tool added to the dock (icon: `ruler`).
- User clicks point A → clicks point B → a measurement line appears with distance label.
- Distance shown in "map units" (percentage-based) and optionally in custom units set by the user.
- Measurements are ephemeral (not saved to DB) — they're a tool, not persistent data.
- Multiple measurements can be active. Clear all with Escape or tool switch.

### Map Scale Setting

**`lib/storyarn/maps/map.ex`** — Add scale fields:
```elixir
field :scale_unit, :string  # "km", "miles", "leagues", "days travel", custom
field :scale_value, :float  # 1 map unit (0-100%) = X real units
```

Example: If the map represents 500km total width, `scale_value: 500, scale_unit: "km"`.
Then a measurement of 20% width = 100km.

**Migration** — `priv/repo/migrations/XXXXXX_add_scale_to_maps.exs`:
```elixir
alter table(:maps) do
  add :scale_unit, :string
  add :scale_value, :float
end
```

### Files to create

**`assets/js/scene_canvas/ruler.js`**
- `createRuler(hook)` factory function.
- State: `measurements` array, `drawing` boolean, `startPoint`.
- When ruler tool active:
  - Click → set start point, show marker.
  - Click again → set end point, draw line + label.
  - Label shows: distance in % + distance in map units (if scale configured).
- Line rendered as dashed polyline with midpoint label.
- Escape → clear all measurements.
- Tool switch → clear all measurements.

### Files to modify

**`assets/js/hooks/scene_canvas.js`**
- Import and init ruler.
- Pass `mapData.scale_unit` and `mapData.scale_value` to ruler.

**`lib/storyarn_web/live/scene_live/show.ex`**
- Include `scale_unit` and `scale_value` in `build_map_data`.
- Add `handle_event("update_map_scale", %{"scale_unit" => unit, "scale_value" => value})`.

**`lib/storyarn_web/live/scene_live/components/properties_panel.ex`**
- In map properties (when nothing selected): add Scale section.
  - Unit input (text, e.g. "km", "leagues")
  - Value input (number, e.g. "500")
  - Help text: "1 map width = {value} {unit}"

**`lib/storyarn_web/live/scene_live/components/dock.ex`**
- Add Ruler tool button (icon: `ruler`).

### Tests

**`test/storyarn/scenes_test.exs`**
- `update_map` with `scale_unit` and `scale_value` stores them.
- `scale_value` must be positive (if set).

**`test/storyarn_web/live/scene_live/show_test.exs`**
- `update_map_scale` persists scale settings.
- `update_map_scale` rejected for viewer.
- Map data serialization includes scale fields.

### Verification
```bash
mix test test/storyarn/scenes_test.exs test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task 4: Map Export (PNG/SVG)

### Overview
Export the current map view as an image file. Renders the canvas (background + all visible elements) to PNG or SVG for use outside Storyarn.

### Design
Two export options:
1. **PNG** — Rasterized screenshot of the canvas. Uses `html2canvas` or Leaflet's built-in tile/image export.
2. **SVG** — Vector export of zones, pins, connections (without background raster). Better for print.

### Implementation Approach — Client-Side Export

**PNG Export:**
Use `leaflet-image` plugin or `html2canvas` to capture the Leaflet container as a canvas element, then convert to PNG blob and trigger download.

**SVG Export:**
Iterate over all visible Leaflet layers, serialize their geometries to SVG elements (polygons for zones, circles/images for pins, polylines for connections), wrap in an SVG document, trigger download.

### Files to create

**`assets/js/scene_canvas/exporter.js`**
- `exportPNG(hook)` → captures canvas, triggers download.
- `exportSVG(hook)` → builds SVG from layer data, triggers download.
- Both respect current layer visibility (hidden layers excluded).

### Files to modify

**`lib/storyarn_web/live/scene_live/show.ex` (template)**
- Add export buttons in the header or settings panel:
  - "Export as PNG" → pushes JS command via `push_event("export_map", %{format: "png"})`.
  - "Export as SVG" → pushes JS command via `push_event("export_map", %{format: "svg"})`.

**`assets/js/hooks/scene_canvas.js`**
- Handle `export_map` event → call `exportPNG` or `exportSVG` from exporter module.

**`assets/package.json`**
- Add `html2canvas` or `leaflet-image` as dependency (for PNG export).

### Tests

**`test/storyarn_web/live/scene_live/show_test.exs`**
- Export buttons render for editor.
- Export buttons do not render for viewer (or render as read-only).

### Verification
```bash
mix test test/storyarn_web/live/scene_live/show_test.exs
mix credo
```

---

## Task Dependency Graph

```
Task 1 (Fog of War) ← no dependencies
Task 2 (Mini-Map) ← no dependencies
Task 3 (Ruler/Distance) ← no dependencies
Task 4 (Map Export) ← no dependencies
```

All tasks are independent and can be done in any order.

**Recommended order:** 1 → 2 → 3 → 4 (Fog of War is the most impactful feature)

## Workflow per Task

1. Read task description carefully
2. Implement the task
3. Run `mix credo` — fix any issues
4. Run `mix test` — all tests pass
5. Ask user for review before moving to next task
