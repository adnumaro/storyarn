# Phase 7.5: World Builder - Maps & Locations

> **Goal:** Add visual world-building tools with interactive maps linked to narrative content
>
> **Priority:** Medium - Enhances world visualization, integrates with existing Sheets/Flows
>
> **Status:** ✅ Feature-complete. All phases done. Audit pass applied (code quality, credo --strict green).
>
> **Next:** Phase 4 (sheet backlinks + variable-triggered layers) — deferred.
>
> **Last Updated:** February 18, 2026
>
> ## New Phase Plans
>
> The original Phase 4+ has been superseded by a complete UX redesign:
>
> | Phase  | Plan File                  | Focus                                                                                                                  | Tasks   | Status     |
> |--------|----------------------------|------------------------------------------------------------------------------------------------------------------------|---------|------------|
> | A      | `WORLD_BUILDER_PHASE_A.md` | Core UX Rewrite — Edit/View modes, dock, shape presets, context menus, pins from sheets, annotations, layer management | 9 tasks | ✅ Complete |
> | B      | `WORLD_BUILDER_PHASE_B.md` | Polish & Connections — Connection feedback, curved paths, search/filter, legend, image pins                            | 5 tasks | ✅ Complete |
> | C      | `WORLD_BUILDER_PHASE_C.md` | Advanced — Fog of War, mini-map, ruler/distance, map export                                                            | 4 tasks | ✅ Complete |

## Overview

This phase adds interactive map capabilities to Storyarn:
- Upload map images and place interactive pins and zones
- Draw polygonal zones to define regions, territories, districts
- Link pins and zones to Sheets (locations, characters) and Flows
- Zones support drill-down navigation (click a region → navigate to its sub-map)
- Layer system for different map states with variable-based triggers
- Map hierarchy for drill-down navigation (world → region → city → building)
- Pins, zones, and connections appear as children of their map in the sidebar tree

**Design Philosophy:** Maps are a visualization layer on top of the existing Sheet/Flow system. They don't replace Sheets — they provide a spatial interface to navigate and understand the world. Zones are first-class navigable elements (like World Anvil polygons), not just decorative shapes.

---

## Progress Summary

### Phase 1: Backend (✅ Complete)
All schemas, migrations, CRUD operations, tree queries, and 54 unit tests.

**Files created:**
- `priv/repo/migrations/20260217140000_create_map_tables.exs`
- `lib/storyarn/maps.ex` (facade)
- `lib/storyarn/maps/map.ex`, `map_layer.ex`, `map_zone.ex`, `map_pin.ex`, `map_connection.ex`
- `lib/storyarn/maps/scene_crud.ex`, `layer_crud.ex`, `zone_crud.ex`, `pin_crud.ex`, `connection_crud.ex`, `tree_operations.ex`
- `test/storyarn/scenes_test.exs`, `test/support/fixtures/scenes_fixtures.ex`

### Phase 2: UI Navigation & CRUD (✅ Complete)
Router, sidebar integration, SceneLive.Index, SceneLive.Form, SceneLive.Show (list-based, no canvas).

**Files created/modified:**
- `lib/storyarn_web/router.ex` — 3 map routes added
- `lib/storyarn_web/components/layouts.ex` — `maps_tree`, `selected_scene_id` attrs
- `lib/storyarn_web/components/project_sidebar.ex` — Maps tool link + `:maps` branch
- `lib/storyarn_web/components/sidebar/scene_tree.ex` — sidebar tree component
- `lib/storyarn_web/live/scene_live/index.ex` — map list page
- `lib/storyarn_web/live/scene_live/form.ex` — create map form (LiveComponent)
- `lib/storyarn_web/live/scene_live/show.ex` — map detail page (layers, zones, pins, connections as lists)

### Phase 3: Leaflet.js Canvas (✅ Complete)
Interactive map canvas with Leaflet.js for drawing zones, placing pins, connecting pins, and background images. 65 LiveView tests, 1777 total tests passing.

**Files created:**
- `assets/js/hooks/scene_canvas.js` — Leaflet.js LiveView hook (thin orchestrator)
- `assets/js/scene_canvas/setup.js` — `L.CRS.Simple` + `L.imageOverlay` init
- `assets/js/scene_canvas/coordinate_utils.js` — percentage ↔ LatLng conversion
- `assets/js/scene_canvas/pin_renderer.js` — `L.divIcon` markers with Lucide icons + tooltips
- `assets/js/scene_canvas/zone_renderer.js` — `L.polygon` with fill/border/dash styling
- `assets/js/scene_canvas/connection_renderer.js` — `L.polyline` between pins
- `assets/js/scene_canvas/vertex_editor.js` — draggable vertex handles, midpoint insert, Ctrl+click remove
- `assets/js/scene_canvas/handlers/pin_handler.js` — pin creation, drag, selection
- `assets/js/scene_canvas/handlers/zone_handler.js` — zone drawing state machine, hover effects
- `assets/js/scene_canvas/handlers/connection_handler.js` — connection drawing state machine
- `assets/js/scene_canvas/handlers/layer_handler.js` — layer visibility toggling
- `lib/storyarn_web/live/scene_live/components/properties_panel.ex` — pin/zone/connection property panels

**Files modified:**
- `lib/storyarn_web/live/scene_live/show.ex` — full-screen canvas layout, toolbar (Pan/Pin/Zone/Connect modes), property panel sidebar, layer bar, all CRUD event handlers
- `test/storyarn_web/live/scene_live/show_test.exs` — 65 tests covering all canvas features

**Implemented features:**
- Toolbar modes: Pan, Pin, Zone, Connect
- Zone drawing (click vertices → double-click to close polygon)
- Zone vertex editing (drag handles, midpoint insert, Ctrl+click remove, min 3 enforced)
- Pin placement (click to create, drag to move with debounce)
- Connection drawing (click source pin → click target pin, preview line follows cursor)
- Property panel (right sidebar adapts to selected element type)
- Layer bar (bottom bar with visibility toggles, active layer selection, add layer)
- Hover interactions (zone opacity increase, pin/zone tooltips)
- Confirm modal pattern for all delete operations (no browser-native dialogs)

### Phase 3: Leaflet.js Canvas (✅ Complete)
Interactive map canvas. Full edit/view modes, toolbar modes, property panels, layer management, undo/redo. 1908 tests passing.

### Phase A: Core UX Rewrite (✅ Complete)
Edit/View modes, dock, shape presets, context menus, pins from sheets, annotations, layer management. 9 tasks.

**Files created:**
- `assets/js/scene_canvas/handlers/annotation_handler.js`
- `lib/storyarn_web/live/scene_live/components/properties_panel.ex`
- Additional migrations: `20260217150000_add_sheet_id_to_map_pins.exs`, `20260217160000_create_map_annotations.exs`, `20260217180000_add_icon_asset_to_pins.exs`

### Phase B: Polish & Connections (✅ Complete)
Connection feedback, curved paths with waypoints, search/filter, legend, image pins. 5 tasks.

**Files created/modified:**
- Migration: `20260217170000_add_waypoints_to_connections.exs`
- `assets/js/scene_canvas/handlers/connection_handler.js` — waypoint editing

### Phase C: Advanced Features (✅ Complete)
Fog of War, scale/ruler, map export (PNG + SVG). 4 tasks.

**Files created/modified:**
- Migration: `20260217190000_add_fog_to_layers.exs`, `20260217200000_add_scale_to_maps.exs`
- `assets/js/scene_canvas/exporter.js` — PNG + SVG export
- `lib/storyarn/maps/map_layer.ex` — fog fields added
- `lib/storyarn/maps/map.ex` — scale fields added

### Audit Pass (✅ Complete — February 18, 2026)
40-issue audit of uncommitted changes. Code quality, dead code removal, security, i18n.

**Summary of changes:**
- Removed dead code: `trigger_sheet/variable/value` fields from `map_layers` (+ migration `20260218010000_remove_trigger_fields_from_map_layers.exs`), dead `reorder_changeset/2`
- New shared modules: `lib/storyarn/maps/position_utils.ex`, `lib/storyarn/maps/changeset_helpers.ex`
- New JS utilities: `assets/js/scene_canvas/color_utils.js`, `assets/js/scene_canvas/context_menu_builder.js`
- Bug fix: `restore_children` now only restores children deleted in the same operation
- Validation: hex color validation on all color fields, waypoint count limit (max 50)
- Security: `escapeXml` strips XML 1.0 control chars in exporter
- i18n: canvas context menus now use `gettext` via `data-i18n` JSON
- Code quality: `mix credo --strict` exits 0, all 1908 tests pass

### Phase 4: Integration & Backlinks (⬜ Deferred)
- Sheet backlinks ("Appears on Maps" section)
- Variable-triggered layer activation
- Read-only viewer mode with hover/click interactions

---

## Architecture

### Domain Model

```
maps
├── id (integer, PK)
├── project_id (FK → projects, on_delete: delete_all)
├── name (string, not null)            # "Kingdom of Eldoria", "Tavern Interior"
├── description (text)
├── parent_id (FK → maps, on_delete: nilify_all)  # drill-down hierarchy
├── background_asset_id (FK → assets, on_delete: nilify_all)
├── width (integer)                    # Background image dimensions
├── height (integer)
├── default_zoom (float, default: 1.0)
├── default_center_x (float, default: 50.0)
├── default_center_y (float, default: 50.0)
├── shortcut (string)                  # e.g., "maps.eldoria"
├── position (integer, default: 0)
├── deleted_at (utc_datetime)          # Soft delete (consistent with sheets/flows)
└── timestamps

map_layers
├── id (integer, PK)
├── scene_id (FK → maps, on_delete: delete_all)
├── name (string, not null)            # "Default", "After the Fire", "Winter"
├── is_default (boolean, default: false)
├── position (integer, default: 0)
├── visible (boolean, default: true)   # Editing visibility state
├── fog_enabled (boolean, default: false)
├── fog_color (string, default: "#1a1a2e")
├── fog_opacity (float, default: 0.85)
└── timestamps
# Note: trigger_sheet/variable/value removed — variable-triggered layers deferred to Phase 4

map_zones                              # Polygonal regions (territories, districts, areas)
├── id (integer, PK)
├── scene_id (FK → maps, on_delete: delete_all)
├── layer_id (FK → map_layers, on_delete: nilify_all)  # nil = visible on all layers
├── name (string, not null)            # "Northern Kingdom", "Market District"
├── vertices (jsonb, not null)         # [{x: 10.5, y: 20.3}, {x: 45.0, y: 15.0}, ...]
├── fill_color (string)                # Hex color with alpha (e.g., "#3b82f640")
├── border_color (string)              # Hex color (e.g., "#3b82f6")
├── border_width (integer, default: 2)
├── border_style (string, default: "solid")  # solid | dashed | dotted
├── opacity (float, default: 0.3)      # Fill opacity 0-1 (0 = invisible but clickable)
├── target_type (string)               # "sheet" | "flow" | "map"
├── target_id (integer)                # FK to linked entity (polymorphic)
├── tooltip (text)                     # Hover text
├── position (integer, default: 0)     # Order in sidebar tree
└── timestamps

map_pins
├── id (integer, PK)
├── scene_id (FK → maps, on_delete: delete_all)
├── layer_id (FK → map_layers, on_delete: nilify_all)  # nil = visible on all layers
├── position_x (float, not null)       # Percentage 0-100 for responsiveness
├── position_y (float, not null)
├── pin_type (string, default: "location")  # location | character | event | custom
├── icon (string)                      # Lucide icon name
├── color (string)                     # Hex color
├── label (string)
├── target_type (string)               # "sheet" | "flow" | "map" | "url"
├── target_id (integer)                # FK to linked entity (polymorphic)
├── tooltip (text)                     # Hover text
├── size (string, default: "md")       # sm | md | lg
├── position (integer, default: 0)     # Order in sidebar tree
└── timestamps

map_connections
├── id (integer, PK)
├── scene_id (FK → maps, on_delete: delete_all)
├── from_pin_id (FK → map_pins, on_delete: delete_all)
├── to_pin_id (FK → map_pins, on_delete: delete_all)
├── line_style (string, default: "solid")  # solid | dashed | dotted
├── color (string)
├── label (string)                     # "3 days travel"
├── bidirectional (boolean, default: true)
└── timestamps
```

### Zones: Key Design Decisions

**Vertices storage:** JSON array of `{x, y}` percentage pairs (0-100), same coordinate system as pins. Stored as `jsonb` in PostgreSQL for efficient querying.

```elixir
# Example: triangle zone
vertices: [
  %{"x" => 20.0, "y" => 10.0},
  %{"x" => 60.0, "y" => 10.0},
  %{"x" => 40.0, "y" => 50.0}
]
```

**Invisible but clickable:** A zone with `opacity: 0` is invisible but still clickable — useful for overlaying interactive regions on a detailed map image without visual clutter (World Anvil pattern).

**Drill-down via zones:** When `target_type == "map"`, clicking the zone navigates to the linked sub-map. This is the primary drill-down mechanism for large worlds (click "Northern Kingdom" region → opens the Northern Kingdom map). This replaces the "portal" pin type — zones handle area-based navigation, pins handle point-based navigation.

### Integration with Existing Systems

```
Maps Integration:
├── Sheets
│   ├── Pins and zones link TO sheets (any sheet — character, location, item, etc.)
│   ├── Backlinks: sheets show "Appears on these maps" in references
│   └── Sheets are type-agnostic — pin_type is on the pin, not the sheet
│
├── Flows
│   ├── Pins and zones link TO flows (start a conversation at this location)
│   └── Zones with target_type=map provide drill-down navigation
│
├── Variables (condition/instruction system)
│   ├── Layers can be triggered by variable values
│   ├── Uses existing {sheet.shortcut}.{variable_name} format
│   └── Example: layer shows when world.state.castle_status == "burned"
│
└── Assets
    └── Map backgrounds are assets (reuse existing upload/storage system)
```

### Module Structure

```
lib/storyarn/maps/                                    # ✅ ALL COMPLETE
├── maps.ex                    # Context facade (defdelegate)
├── map.ex                     # Map schema + changesets
├── map_layer.ex               # Layer schema + changesets
├── map_zone.ex                # Zone schema + changesets (polygon vertices)
├── map_pin.ex                 # Pin schema + changesets
├── map_connection.ex          # Connection schema + changesets
├── scene_crud.ex                # Map CRUD + hierarchy + tree queries
├── layer_crud.ex              # Layer CRUD + reorder + visibility toggle
├── zone_crud.ex               # Zone CRUD + vertex updates
├── pin_crud.ex                # Pin CRUD + move + target linking
├── connection_crud.ex         # Connection CRUD
└── tree_operations.ex         # Reorder + move-to-position

lib/storyarn_web/live/scene_live/                       # ✅ Phase 2 COMPLETE
├── index.ex                   # Map list with create/delete
├── show.ex                    # Map detail (layers, zones, pins, connections lists)
└── form.ex                    # LiveComponent: create map form

lib/storyarn_web/components/sidebar/                  # ✅ COMPLETE
└── scene_tree.ex                # Maps section in project sidebar (search, sortable tree)

assets/js/hooks/                                      # ⬜ Phase 3 PENDING
└── scene_canvas.js              # Leaflet.js LiveView hook (pins, zones, connections)
```

---

## Implementation Tasks

### 7.5.M.1 Maps Table & CRUD ✅

#### Database & Schema
- [x] Create `maps` table (migration) — `priv/repo/migrations/20260217140000_create_map_tables.exs`
- [x] Unique index on `(project_id, shortcut)` where shortcut is not null and deleted_at is null
- [x] Index on `(project_id, parent_id)` for hierarchy
- [x] Index on `(project_id)` for listing
- [x] Schema: `Map` with `create_changeset/2`, `update_changeset/2` — `lib/storyarn/maps/map.ex`
- [x] Shortcut validation (same regex as sheets/flows)

#### Context Functions
- [x] `Maps.list_maps/1` - List all maps in project (flat, ordered by position then name)
- [x] `Maps.list_maps_tree/1` - List maps as tree structure with children preloaded
- [x] `Maps.get_map/2` - Get map with layers, zones, pins, connections preloaded
- [x] `Maps.get_map!/2` - Get map, raise if not found
- [x] `Maps.create_map/2` - Create new map (auto-create default layer, auto-generate shortcut)
- [x] `Maps.update_map/2` - Update map properties (auto-regenerate shortcut on name change)
- [x] `Maps.delete_map/1` - Soft delete map (+ recursive children)
- [x] `Maps.reorder_maps/3` - Change map order among siblings
- [x] `Maps.move_map_to_position/3` - Move map to different parent at position
- [x] `Maps.restore_map/1` - Restore soft-deleted map
- [x] `Maps.list_deleted_maps/1` - List trashed maps
- [x] `Maps.search_maps/2` - Search maps by name/shortcut
- [x] `Maps.change_map/2` - Changeset for forms

#### Map Hierarchy
Maps use the same tree pattern as sheets/flows:
```
World Map (parent_id: nil)
├── Northern Kingdom (parent_id: world_map.id)
│   ├── Capital City
│   │   ├── Royal Palace
│   │   └── Market District
│   └── Dark Forest
└── Southern Empire
```

---

### 7.5.M.2 Map Layers ✅

#### Database & Schema
- [x] Create `map_layers` table (migration) — same migration file
- [x] Index on `(scene_id, position)`
- [x] Schema: `MapLayer` with changesets — `lib/storyarn/maps/map_layer.ex`

#### Context Functions
- [x] `Maps.list_layers/1` - List layers for a map (ordered by position)
- [x] `Maps.create_layer/2` - Create new layer (auto-assigned position)
- [x] `Maps.update_layer/2` - Update layer (name, trigger config)
- [x] `Maps.delete_layer/1` - Delete layer (returns error if last layer; nullifies zone/pin layer_ids)
- [x] `Maps.reorder_layers/2` - Change layer order
- [x] `Maps.toggle_layer_visibility/1` - Show/hide layer in editor
- [x] `Maps.change_layer/2` - Changeset for forms

#### Default Layer
Every map has at least one layer, auto-created when the map is created.

#### Variable-Based Triggers
Layers can link to a sheet variable to determine when they're active:

```
Layer: "After the Fire"
├── trigger_sheet: "world.state"          # Sheet shortcut
├── trigger_variable: "castle_status"     # Block variable_name
└── trigger_value: "burned"               # Expected value

→ Layer becomes active when world.state.castle_status == "burned"
```

This reuses the existing variable system (condition/instruction nodes already read/write these variables). No new node types needed.

**Use Cases:**
- Before/after story events (castle burns, army arrives)
- Seasonal changes (winter/summer)
- Quest progress (reveal hidden locations)
- Game state variations

---

### 7.5.M.3 Map Zones ✅

Polygonal regions that define interactive areas on the map. Zones are first-class navigable elements — clicking a zone navigates to linked content or drills down to a sub-map.

#### Database & Schema
- [x] Create `map_zones` table (migration) — same migration file
- [x] Index on `(scene_id, layer_id)`
- [x] Index on `(target_type, target_id)`
- [x] Schema: `MapZone` with changesets — `lib/storyarn/maps/map_zone.ex`
- [x] Vertex validation (minimum 3 points, all within 0-100 range)

#### Context Functions
- [x] `Maps.list_zones/2` - List zones for map (optionally filtered by layer)
- [x] `Maps.create_zone/2` - Create new zone with initial vertices (auto-position)
- [x] `Maps.update_zone/2` - Update zone properties (name, style, target)
- [x] `Maps.update_zone_vertices/2` - Update zone polygon shape (optimized for drag)
- [x] `Maps.delete_zone/1` - Delete zone (hard delete)
- [x] `Maps.change_zone/2` - Changeset for forms

#### Zone Drawing

Users draw zones by clicking points on the map to define vertices:
1. Enter "Zone Mode" via toolbar
2. Click to place each vertex
3. Click the first vertex again (or double-click) to close the polygon
4. The zone is created with default styling and appears in the sidebar tree

**Vertex editing:**
- Select a zone → vertices become draggable handles
- Click a border segment → inserts a new vertex at that point
- Ctrl+click a vertex → removes it (minimum 3 vertices enforced)

#### Zone Styling

| Property     | Default   | Purpose                                         |
|--------------|-----------|-------------------------------------------------|
| fill_color   | `#3b82f6` | Interior color                                  |
| opacity      | `0.3`     | Fill transparency (0 = invisible but clickable) |
| border_color | `#3b82f6` | Outline color                                   |
| border_width | `2`       | Outline thickness in pixels                     |
| border_style | `solid`   | solid / dashed / dotted                         |

#### Responsive Positioning
Same percentage-based system as pins — vertices stored as `{x, y}` percentages (0-100):
```elixir
vertices: [%{"x" => 20.0, "y" => 10.0}, %{"x" => 60.0, "y" => 10.0}, %{"x" => 40.0, "y" => 50.0}]
```

---

### 7.5.M.4 Map Pins ✅

#### Database & Schema
- [x] Create `map_pins` table (migration) — same migration file
- [x] Index on `(scene_id, layer_id)`
- [x] Index on `(target_type, target_id)`

#### Context Functions
- [x] `Maps.list_pins/2` - List pins for map (optionally filtered by layer)
- [x] `Maps.create_pin/2` - Create new pin (auto-position)
- [x] `Maps.update_pin/2` - Update pin properties (target, style, tooltip)
- [x] `Maps.move_pin/3` - Update pin position (optimized for drag)
- [x] `Maps.delete_pin/1` - Delete pin (hard delete, cascades connections)
- [x] `Maps.change_pin/2` - Changeset for forms

#### Pin Types

| Type      | Default Icon   | Purpose                          | Typical Target |
|-----------|----------------|----------------------------------|----------------|
| location  | map-pin        | Mark places                      | Sheet          |
| character | user           | Character home/current location  | Sheet          |
| event     | zap            | Story events                     | Flow           |
| custom    | circle         | User-defined                     | Any            |

Icons use Lucide names (consistent with the rest of the app). Pin type is cosmetic — it determines the default icon/color but doesn't constrain the target.

Note: "portal" pin type removed — zones handle area-based drill-down navigation to sub-maps. Pins that need to link to maps can still set `target_type: "map"`.

#### Responsive Positioning
Positions stored as percentages (0-100), not pixels:
```
position_x: 45.5  # 45.5% from left
position_y: 30.0  # 30% from top
```

---

### 7.5.M.5 Map Connections ✅

Visual lines connecting pins (travel routes, relationships).

#### Database & Schema
- [x] Create `map_connections` table (migration) — same migration file
- [x] Index on `(scene_id)`

#### Context Functions
- [x] `Maps.list_connections/1` - List connections for map (with from_pin/to_pin preloaded)
- [x] `Maps.create_connection/2` - Create connection between pins (validates same map)
- [x] `Maps.update_connection/2` - Update style/label
- [x] `Maps.delete_connection/1` - Delete connection (hard delete)
- [x] `Maps.change_connection/2` - Changeset for forms

#### Line Styles
- `solid` — main roads, clear paths
- `dashed` — secondary routes, uncertain paths
- `dotted` — hidden/secret passages

---

### 7.5.M.6 Map Editor UI (Phase 3 — Leaflet Canvas) ⬜

Main interface for creating and editing maps. **Requires Leaflet.js integration.**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ MAP EDITOR: Kingdom of Eldoria                    [Layers ▼] [Settings]     │
├────────────────────────────────────────────────────────┬────────────────────┤
│                                                        │ PROPERTIES         │
│    ┌──────────────────────────────────────────────┐   │                    │
│    │        ┌─────────────────────┐               │   │ Selected:          │
│    │        │  Northern Kingdom   │ <-- zone      │   │ "Northern Kingdom" │
│    │        │  (filled polygon)   │               │   │ Type: Zone         │
│    │        │     ★ Capital       │ <-- pin       │   │                    │
│    │        │         ○ Village   │               │   │ Fill: [#3b82f640]  │
│    │        └─────────────────────┘               │   │ Border: [#3b82f6] │
│    │                                              │   │ Opacity: [0.3]     │
│    │    ┌──────────────┐                          │   │ Style: [Solid ▼]   │
│    │    │ Dark Forest  │ <-- zone (dashed border) │   │                    │
│    │    │  ○ Ruins     │                          │   │ Links to:          │
│    │    └──────────────┘                          │   │ Northern Kingdom   │
│    │                                              │   │ (Map - drill down) │
│    │    ○ Jaime's House  <-- pin                  │   │ [Change Target]    │
│    │                                              │   │                    │
│    │    [Background: world_map.png]               │   │ Tooltip:           │
│    │                                              │   │ [The frozen north] │
│    └──────────────────────────────────────────────┘   │                    │
│                                                        │ Layer: [Default ▼] │
│ [Zoom] [Pan] [Pin Mode] [Zone Mode] [Connect Mode]    │ [Delete]           │
├────────────────────────────────────────────────────────┴────────────────────┤
│ LAYERS                                                      [+ Add Layer]   │
│ [eye] Default          [eye] After the War (castle_status = burned)         │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Implementation Tasks
- [ ] LiveView: `SceneLive.Edit`
- [ ] Leaflet.js hook (`scene_canvas.js`) with simple CRS for image overlay
- [ ] Background image upload (reuse asset upload system)
- [ ] **Toolbar modes:**
  - Pan Mode (default — drag to pan)
  - Pin Mode (click to place pin)
  - Zone Mode (click vertices to draw polygon, close to create zone)
  - Connect Mode (click source pin → click target pin)
- [ ] Pin placement: click to place, drag to move
- [ ] Zone drawing: click vertices, close polygon, create zone
- [ ] Zone vertex editing: drag handles, add/remove vertices
- [ ] Selection → property panel (right sidebar, adapts to pin vs zone)
- [ ] Target selector (search sheets/flows/maps)
- [ ] Layer visibility toggles
- [ ] Layer management panel (add, edit trigger, reorder, delete)
- [ ] Zoom/pan controls

#### Property Panel (right sidebar)

**When a zone is selected:**
- Name (text input)
- Fill color (color picker)
- Opacity (slider 0-1)
- Border color (color picker)
- Border width (number)
- Border style (select: solid/dashed/dotted)
- Links to (target selector — sheet/flow/map)
- Tooltip (textarea)
- Layer (select)
- Delete Zone (button)

**When a pin is selected:**
- Label (text input)
- Type (select: location/character/event/custom)
- Icon (Lucide icon name)
- Color (color picker)
- Size (select: sm/md/lg)
- Links to (target selector)
- Tooltip (textarea)
- Layer (select)
- Delete Pin (button)

**When nothing is selected:**
- Map info (name, dimensions, shortcut)
- Upload/change background image button

---

### 7.5.M.7 Map Viewer UI (Phase 3 — Leaflet Canvas) ⬜

Read-only view for navigating the map. **Requires Leaflet.js integration.**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ World Map > Northern Kingdom                                  [Edit Mode]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │                                                                  │    │
│    │        ┌─────────────────────┐                                   │    │
│    │        │  Northern Kingdom   │ <-- hover highlights zone         │    │
│    │        │                     │     click → drills down to map    │    │
│    │        │     ★ Capital City  │ <-- click pin → popup             │    │
│    │        │         ○ Village   │     ┌─────────────────────────┐   │    │
│    │        └─────────────────────┘     │ Capital City             │   │    │
│    │                                    │ The heart of the kingdom │   │    │
│    │    ┌──────────────┐                │ [Open Sheet] [Open Flow] │   │    │
│    │    │ Dark Forest  │                └─────────────────────────┘   │    │
│    │    │  ○ Ruins     │                                              │    │
│    │    └──────────────┘                                              │    │
│    │                                                                  │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│ Layers: [Default ✓] [After War ○]                  [<- Back to World Map]  │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Interaction Model

**Zones:**
- Hover → zone highlights (increased opacity + border glow)
- Hover → tooltip appears if configured
- Click → if `target_type == "map"`: navigates to linked sub-map (drill-down)
- Click → if `target_type == "sheet"/"flow"`: popup with "Open Sheet"/"Open Flow" link

**Pins:**
- Hover → tooltip
- Click → popup with name, tooltip text, and action buttons:
  - "Open Sheet" (if target is sheet)
  - "Open Flow" (if target is flow)
  - "Open Map" (if target is map)

**Connections:**
- Visible as lines with optional labels
- Not interactive (visual only)

#### Implementation Tasks
- [ ] LiveView: `SceneLive.Show`
- [ ] Read-only Leaflet.js canvas with pan/zoom
- [ ] Zone rendering as `L.polygon` with hover highlight
- [ ] Zone click → drill-down navigation or popup
- [ ] Pin hover tooltips (Leaflet popups)
- [ ] Pin click → popup with actions
- [ ] Breadcrumb for map hierarchy (`World Map > Northern Kingdom > Capital`)
- [ ] Layer toggle for viewers
- [ ] "Back to [Parent Map]" button

---

### 7.5.M.8 Maps in Project Sidebar — Partially Done ✅/⬜

Integration with project sidebar for navigation. Maps show their children (zones and pins) in the tree.

```
┌─────────────────────────┐
│ PROJECT SIDEBAR         │
├─────────────────────────┤
│ Flows                   │
│ Screenplays             │
│ Sheets                  │
│ Maps                    │  <-- New tool link
│ Assets                  │
│ Localization            │
├─────────────────────────┤
│ (active tool tree)      │
│ World Map               │  <-- When Maps is active
│ ├── ◇ Northern Kingdom  │  <-- zone (diamond icon)
│ ├── ◇ Southern Empire   │  <-- zone
│ ├── ◇ Dark Forest       │  <-- zone
│ ├── ○ Capital City      │  <-- pin
│ ├── ○ Jaime's House     │  <-- pin
│ └── ○ Ancient Ruins     │  <-- pin
│ Tavern Interior         │  <-- another root map
│ └── ○ Bar Counter       │
└─────────────────────────┘
```

**Icons in tree:**
- Maps: `map` (Lucide)
- Zones: `pentagon` or `hexagon` (Lucide) — polygon shape
- Pins: `map-pin` (Lucide) or the pin's configured icon

**Click behavior:**
- Click a map → opens `SceneLive.Show` (viewer)
- Click a zone → opens `SceneLive.Show` and highlights/centers on that zone
- Click a pin → opens `SceneLive.Show` and highlights/centers on that pin

#### Implementation Tasks
- [x] Add "Maps" tool link to project sidebar (Lucide icon: `map`) — `project_sidebar.ex`
- [x] Create `SceneTree` component (same pattern as `FlowTree`) — `lib/storyarn_web/components/sidebar/scene_tree.ex`
- [x] Tree view: maps as hierarchical tree with children
- [ ] Tree view: zones + pins as children of maps (requires canvas phase — currently zones/pins are only created via canvas)
- [ ] Different icons for maps vs zones vs pins in tree (maps use `map`; zone/pin icons pending canvas integration)
- [x] Context menu: New Map, New Child Map, Move to Trash
- [x] Drag to reorder maps among siblings (SortableTree hook)

---

### 7.5.M.9 Sheet Backlinks ⬜

Show which maps a sheet appears on (via pins or zones).

When a pin or zone's `target_type` is `"sheet"` and `target_id` points to a sheet, that sheet displays an "Appears on Maps" section in its references.

```
┌─────────────────────────────────────────────────────────────────┐
│ SHEET: Capital City                                              │
├─────────────────────────────────────────────────────────────────┤
│ [Content] [References]                                           │
├─────────────────────────────────────────────────────────────────┤
│ APPEARS ON MAPS                                                  │
│ ├── World Map (pin: "Capital City")          [View on Map ->]    │
│ ├── World Map (zone: "Northern Kingdom")     [View on Map ->]    │
│ └── Northern Kingdom (pin: "The Capital")    [View on Map ->]    │
│                                                                   │
│ BACKLINKS                                                        │
│ └── ...                                                          │
└─────────────────────────────────────────────────────────────────┘
```

#### Implementation Tasks
- [ ] Query: `Maps.get_elements_for_target("sheet", sheet_id)` — returns pins + zones with preloaded map
- [ ] Add "Appears on Maps" section to sheet references UI
- [ ] "View on Map" link navigates to `SceneLive.Show` with the element highlighted/centered

---

## Database Migration

Single migration for all map tables:

```elixir
# priv/repo/migrations/XXXX_create_map_tables.exs

# -- Maps --
create table(:maps) do
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  add :name, :string, null: false
  add :description, :text
  add :parent_id, references(:maps, on_delete: :nilify_all)
  add :background_asset_id, references(:assets, on_delete: :nilify_all)
  add :width, :integer
  add :height, :integer
  add :default_zoom, :float, default: 1.0
  add :default_center_x, :float, default: 50.0
  add :default_center_y, :float, default: 50.0
  add :shortcut, :string
  add :position, :integer, default: 0
  add :deleted_at, :utc_datetime

  timestamps(type: :utc_datetime)
end

create unique_index(:maps, [:project_id, :shortcut],
  where: "shortcut IS NOT NULL AND deleted_at IS NULL",
  name: :maps_project_shortcut_unique)
create index(:maps, [:project_id, :parent_id])
create index(:maps, [:project_id])

# -- Map Layers --
create table(:map_layers) do
  add :scene_id, references(:maps, on_delete: :delete_all), null: false
  add :name, :string, null: false
  add :is_default, :boolean, default: false, null: false
  add :trigger_sheet, :string
  add :trigger_variable, :string
  add :trigger_value, :string
  add :position, :integer, default: 0
  add :visible, :boolean, default: true, null: false

  timestamps(type: :utc_datetime)
end

create index(:map_layers, [:scene_id, :position])

# -- Map Zones --
create table(:map_zones) do
  add :scene_id, references(:maps, on_delete: :delete_all), null: false
  add :layer_id, references(:map_layers, on_delete: :nilify_all)
  add :name, :string, null: false
  add :vertices, :jsonb, null: false    # [{x, y}, ...] percentage-based
  add :fill_color, :string, default: "#3b82f6"
  add :border_color, :string, default: "#3b82f6"
  add :border_width, :integer, default: 2
  add :border_style, :string, default: "solid"
  add :opacity, :float, default: 0.3
  add :target_type, :string
  add :target_id, :integer
  add :tooltip, :text
  add :position, :integer, default: 0

  timestamps(type: :utc_datetime)
end

create index(:map_zones, [:scene_id, :layer_id])
create index(:map_zones, [:target_type, :target_id])

# -- Map Pins --
create table(:map_pins) do
  add :scene_id, references(:maps, on_delete: :delete_all), null: false
  add :layer_id, references(:map_layers, on_delete: :nilify_all)
  add :position_x, :float, null: false
  add :position_y, :float, null: false
  add :pin_type, :string, default: "location"
  add :icon, :string
  add :color, :string
  add :label, :string
  add :target_type, :string
  add :target_id, :integer
  add :tooltip, :text
  add :size, :string, default: "md"
  add :position, :integer, default: 0

  timestamps(type: :utc_datetime)
end

create index(:map_pins, [:scene_id, :layer_id])
create index(:map_pins, [:target_type, :target_id])

# -- Map Connections --
create table(:map_connections) do
  add :scene_id, references(:maps, on_delete: :delete_all), null: false
  add :from_pin_id, references(:map_pins, on_delete: :delete_all), null: false
  add :to_pin_id, references(:map_pins, on_delete: :delete_all), null: false
  add :line_style, :string, default: "solid"
  add :color, :string
  add :label, :string
  add :bidirectional, :boolean, default: true, null: false

  timestamps(type: :utc_datetime)
end

create index(:map_connections, [:scene_id])
```

---

## Implementation Order

| Order | Task                                        | Status  | Testable Outcome                              |
|-------|---------------------------------------------|---------|-----------------------------------------------|
| 1     | Maps table + CRUD                           | ✅       | Can create/list/delete maps                   |
| 2     | Map layers table + CRUD                     | ✅       | Can add layers (default auto-created)         |
| 3     | Map zones table + CRUD                      | ✅       | Can create zones with vertices                |
| 4     | Map pins table + CRUD                       | ✅       | Can add/move/delete pins                      |
| 5     | Map connections CRUD                        | ✅       | Can create connections between pins           |
| 6     | Maps sidebar section + tree                 | ✅       | Maps tool link, tree with search/sort/menu    |
| 7     | SceneLive.Index + Form                        | ✅       | List maps, create via modal, delete           |
| 8     | SceneLive.Show (list-based, no canvas)        | ✅       | Detail page: layers, zones, pins, connections |
| 9     | Basic map editor (Leaflet canvas + bg)      | ✅       | Can upload map image, pan/zoom                |
| 10    | Zone drawing UI                             | ✅       | Can draw polygonal zones on map               |
| 11    | Zone vertex editing                         | ✅       | Can reshape zones (drag/add/remove vertices)  |
| 12    | Pin placement UI                            | ✅       | Can place pins on map by clicking             |
| 13    | Property panel (zones + pins)               | ✅       | Can configure style, target, tooltip          |
| 14    | Target selector (link to sheets/flows/maps) | ✅       | Elements link to content                      |
| 15    | Map viewer (read-only Leaflet)              | ✅       | Can navigate map, hover/click zones and pins  |
| 16    | Zone drill-down                             | ✅       | Click zone → navigates to linked sub-map      |
| 17    | Layer visibility toggle in canvas           | ✅       | Can show/hide layers in editor/viewer         |
| 18    | Fog of War + scale/ruler + map export       | ✅       | Fog per layer, scale bar, export PNG/SVG      |
| 19    | Connection drawing UI + waypoints           | ✅       | Can draw routes between pins on canvas        |
| 20    | Audit pass (code quality + credo)           | ✅       | mix credo --strict exits 0, 1908 tests pass   |
| 21    | Sheet backlinks UI                          | ⬜       | Deferred to Phase 4                           |
| 22    | Variable-triggered layers                   | ⬜       | Deferred to Phase 4                           |

---

## Technical Considerations

### Canvas: Leaflet.js

Use [Leaflet.js](https://leafletjs.com/) with simple CRS (non-geographic coordinate system) for image overlays.

**Why Leaflet:**
- Battle-tested pan/zoom with touch/mobile support
- `L.CRS.Simple` mode for non-geo images
- `L.imageOverlay` for map backgrounds
- `L.polygon` for zones (with hover/click events, styling, vertex editing)
- `L.marker` / `L.divIcon` for customizable pins
- `L.polyline` for connections
- Small bundle (~40KB gzipped)
- No conflicts with existing JS libraries (Rete.js, Tiptap, Lit)

**Zone drawing with Leaflet:**
```javascript
// Drawing mode: collect clicks, show preview polygon
let vertices = [];
map.on('click', (e) => {
  vertices.push(e.latlng);
  previewPolygon.setLatLngs(vertices);
});

// Close polygon (click first vertex or double-click)
// → pushEvent("create_zone", { vertices: toPercentages(vertices) })
```

**Vertex editing with Leaflet:**
- Use `L.polygon` with `editable: true` (via Leaflet.Editable plugin)
- Or custom draggable markers at each vertex position
- On drag end → `pushEvent("update_zone_vertices", { id, vertices })`

**Hook Pattern:**
```javascript
// assets/js/hooks/scene_canvas.js
export default {
  mounted() {
    this.map = L.map(this.el, { crs: L.CRS.Simple, ... })
    this.zones = L.layerGroup().addTo(this.map)
    this.pins = L.layerGroup().addTo(this.map)
    this.connections = L.layerGroup().addTo(this.map)
    // Render from server data, bind events
  },
  updated() {
    // Sync zones/pins/layers from server
  },
  destroyed() {
    this.map.remove()
  }
}
```

### Responsive Positioning

All coordinates stored as percentages (0-100) — both pin positions and zone vertices:

```javascript
// Convert percentage to Leaflet coordinates
const toLatLng = (x, y) => L.latLng(
  (y / 100) * imageHeight,
  (x / 100) * imageWidth
)

// Convert Leaflet coordinates back to percentage
const toPercent = (latLng) => ({
  x: (latLng.lng / imageWidth) * 100,
  y: (latLng.lat / imageHeight) * 100
})
```

### Performance
- Lazy load zones/pins when map is opened
- Use asset thumbnails for map list previews
- Leaflet handles rendering efficiently for hundreds of elements
- Cache layer visibility state in localStorage

---

## Testing Strategy

### Unit Tests
- [x] Map CRUD operations (create, update, soft delete, hierarchy) — 54 tests in `test/storyarn/scenes_test.exs`
- [x] Zone vertex validation (minimum 3 points, all within 0-100 range)
- [x] Pin position validation (0-100 range)
- [x] Layer default enforcement (auto-create on map creation)
- [x] Target link validation (target_type + target_id consistency)
- [x] Shortcut format validation (same rules as sheets/flows)
- [x] Connection validation (pins must belong to same map)

### Integration Tests
- [ ] Create map with background image (asset integration)
- [x] Create zones with vertices and link to maps (drill-down)
- [x] Add pins and link to sheets/flows
- [x] Layer CRUD + variable trigger configuration
- [x] Hierarchy: create child maps, move between parents
- [x] Sheet backlinks query (from both pins and zones) — `Maps.get_elements_for_target/2`

### E2E Tests
- [ ] Full map creation workflow (upload background → draw zones → place pins → link)
- [ ] Zone drawing: click vertices → close polygon → zone appears
- [ ] Zone vertex editing: drag, add, remove vertices
- [ ] Zone drill-down: click zone → navigates to sub-map
- [ ] Pin placement and drag-to-move
- [ ] Navigate via map to sheet/flow
- [ ] Layer toggle in viewer

---

## Open Questions

1. **Multiple references per sheet?** Can a sheet be linked from multiple pins/zones?
   - Decision: Yes — many pins/zones can target the same sheet

2. **Pin clustering?** What happens when many pins overlap at low zoom?
   - Recommendation: Defer — Leaflet has a clustering plugin if needed later

3. **Real-time collaboration?** Should map editing be collaborative?
   - Recommendation: Defer — single editor for now (viewer is always fine)

4. **Mini-map on sheets?** Show small map preview on location sheets?
   - Recommendation: Defer — the backlinks section with "View on Map" links is sufficient

5. **Connection routing?** Should connections avoid overlapping pins?
   - Recommendation: Straight lines for now — curved/routed paths are a future enhancement

6. **Zone overlap?** What happens when zones overlap on click?
   - Recommendation: Top-most zone (highest position) receives the click. User can reorder zones in sidebar.

---

## Success Criteria

**Phase 1+2 (Backend + UI Navigation) ✅:**
- [x] Maps appear in the project sidebar with tree navigation
- [x] Can create/edit/delete maps via UI (Index, Show, sidebar tree)
- [x] Map hierarchy works (parent/child with drag reorder in sidebar)
- [x] SceneLive.Show displays layers, zones, pins, connections as lists
- [x] Layer CRUD works from Show page (create, toggle visibility, delete with last-layer protection)
- [x] All backend CRUD for maps, layers, zones, pins, connections (54 tests)

**Phases 3 + A + B + C (Canvas — complete) ✅:**
- [x] Can create maps with uploaded background images
- [x] Can draw polygonal zones to define regions/territories on canvas
- [x] Can place pins to mark specific locations by clicking canvas
- [x] Zones and pins link to Sheets/Flows/Maps via target selector
- [x] Clicking a zone with target_type=map drills down to the linked sub-map
- [x] Can navigate world via interactive map (pan, zoom, hover, click)
- [x] Layers toggle visibility on canvas
- [x] Connections visualize routes between pins on canvas, with waypoints
- [x] Fog of War per layer (color + opacity)
- [x] Scale / ruler display
- [x] Map export (PNG + SVG)
- [x] Annotations (sticky notes)
- [x] Context menus on all element types
- [x] Undo/redo (Ctrl+Z / Ctrl+Y)
- [x] Element locking
- [x] Search within map elements
- [x] mix credo --strict exits 0, 1908 tests pass

**Phase 4 (Integration — Deferred) ⬜:**
- [ ] Sheets show which maps they appear on (backlinks from pins + zones)
- [ ] Variable-triggered layers react to game state

---

## Comparison: World Anvil vs Storyarn

| Feature              | World Anvil                | Storyarn                         |
|----------------------|----------------------------|----------------------------------|
| Interactive maps     | Yes (pins, labels)         | Yes (Leaflet.js)                 |
| Polygonal zones      | Yes (Grandmaster tier)     | Yes (all users)                  |
| Zone drill-down      | Yes (polygon → linked map) | Yes (zone → sub-map)             |
| Invisible zones      | Yes (opacity 0, clickable) | Yes (opacity slider)             |
| Link to content      | Yes (articles)             | Yes (sheets + flows)             |
| Layer system         | Basic (manual)             | Variable-triggered (automatic)   |
| Map hierarchy        | Via linked maps            | Tree hierarchy with breadcrumb   |
| Travel routes        | No                         | Yes (connections between pins)   |
| Variable integration | No                         | Yes (layers react to game state) |
| Sidebar tree         | Category list              | Tree with zones/pins as children |
| Collaboration        | View only                  | View (edit: future)              |

**Key Advantages:**
- Variable-triggered layers = maps react to narrative state automatically
- Zones as first-class tree elements with drill-down navigation
- Direct Flow/Sheet integration = maps are part of the narrative, not separate
- Hierarchy for scale (world → building) with breadcrumb navigation
- Same sidebar tree pattern as Sheets/Flows for consistency
- No tier restrictions — all zone features available to all users

---

## Future Enhancements (Not in Scope)

- **Animated pins** - Pins that move along paths (character travel)
- **Heat maps** - Visualize where story events cluster
- **Pin clustering** - Auto-group dense pin areas at low zoom
- **Custom pin shapes** - Beyond circles (shields, skulls, custom SVGs)
- **Freehand paths** - Draw rivers, roads as curved lines (articy-style)
- **Zone labels** - Configurable text labels rendered inside zones
- **Real-time collaboration** - Multi-user simultaneous map editing
- **Mini-map overlay** - Small overview of the full map when zoomed in

---

*This phase depends on the existing Asset system for map backgrounds and the Variable system (sheets/blocks) for layer triggers. No new flow node types are required.*
