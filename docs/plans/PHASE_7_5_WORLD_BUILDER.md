# Phase 7.5: World Builder - Maps & Locations

> **Goal:** Add visual world-building tools with interactive maps linked to narrative content
>
> **Priority:** Medium - Enhances world visualization, integrates with existing Pages/Flows
>
> **Last Updated:** February 2, 2026

## Overview

This phase adds interactive map capabilities to Storyarn:
- Upload map images and place interactive pins
- Link pins to Pages (locations, characters) and Flows
- Layer system for different map states (before/after events)
- Integration with Flow Event nodes for dynamic map changes
- Relationship visualization between locations

**Design Philosophy:** Maps are a visualization layer on top of the existing Page/Flow system. They don't replace Pages - they provide a spatial interface to navigate and understand the world.

---

## Architecture

### Domain Model

```
maps                          # NEW TABLE
├── id
├── project_id (FK)
├── name                      # "Kingdom of Eldoria", "Tavern Interior"
├── description
├── parent_map_id (FK)        # For drill-down (world → region → city → building)
├── background_asset_id (FK)  # The map image
├── width                     # Canvas dimensions (for pin positioning)
├── height
├── default_zoom
├── default_center_x
├── default_center_y
├── shortcut                  # For references: #maps.eldoria
├── position                  # Order in map list
└── timestamps

map_layers                    # NEW TABLE
├── id
├── map_id (FK)
├── name                      # "Default", "After the Fire", "Winter"
├── is_default                # boolean - shown by default
├── trigger_event_id          # Links to Flow Event node (optional)
├── position                  # Layer order
├── visible                   # Current visibility state (for editing)
└── timestamps

map_pins                      # NEW TABLE
├── id
├── map_id (FK)
├── layer_id (FK)             # Which layer this pin belongs to (nullable = all layers)
├── position_x                # Percentage-based (0-100) for responsiveness
├── position_y
├── pin_type                  # "location" | "character" | "event" | "custom"
├── icon                      # Icon name or emoji
├── color                     # Pin color
├── label                     # Display label
├── target_type               # "page" | "flow" | "map" | "url"
├── target_id                 # UUID of linked entity
├── target_shortcut           # Cached for display
├── tooltip                   # Hover text
├── size                      # "sm" | "md" | "lg"
└── timestamps

map_connections               # NEW TABLE (optional - for travel routes)
├── id
├── map_id (FK)
├── from_pin_id (FK)
├── to_pin_id (FK)
├── line_style                # "solid" | "dashed" | "dotted"
├── color
├── label                     # "3 days travel"
├── bidirectional             # boolean
└── timestamps
```

### Integration with Existing Systems

```
Maps Integration:
├── Pages
│   ├── Location pages can link TO maps (map_id field on page)
│   ├── Pins can link TO pages (character, location, item)
│   └── Backlinks show "This location appears on these maps"
│
├── Flows
│   ├── Pins can link TO flows (start a conversation at this location)
│   ├── Event nodes can trigger layer changes
│   └── FlowJump node can show location on map (visual feedback)
│
└── Assets
    └── Map backgrounds are assets (reuse existing system)
```

---

## Implementation Tasks

### 7.5.M.1 Maps Table & CRUD

#### Database & Schema
- [ ] Create `maps` table (migration)
- [ ] Add unique index on `(project_id, shortcut)` where shortcut is not null
- [ ] Add index on `(project_id, parent_map_id)` for hierarchy

#### Context Functions
- [ ] `Maps.list_maps/1` - List all maps in project (with hierarchy)
- [ ] `Maps.get_map/1` - Get map with layers and pins preloaded
- [ ] `Maps.create_map/2` - Create new map
- [ ] `Maps.update_map/2` - Update map properties
- [ ] `Maps.delete_map/1` - Delete map (cascade pins, layers)
- [ ] `Maps.reorder_maps/2` - Change map order

#### Map Hierarchy
Maps can be nested for drill-down navigation:
```
🗺️ World Map (continent level)
├── 🗺️ Northern Kingdom (region)
│   ├── 🗺️ Capital City (city)
│   │   ├── 🗺️ Royal Palace (building)
│   │   └── 🗺️ Market District (district)
│   └── 🗺️ Dark Forest (area)
└── 🗺️ Southern Empire (region)
```

---

### 7.5.M.2 Map Layers

#### Database & Schema
- [ ] Create `map_layers` table (migration)
- [ ] Add index on `(map_id, position)`

#### Context Functions
- [ ] `Maps.list_layers/1` - List layers for a map
- [ ] `Maps.create_layer/2` - Create new layer
- [ ] `Maps.update_layer/2` - Update layer (name, trigger)
- [ ] `Maps.delete_layer/1` - Delete layer (reassign pins to default?)
- [ ] `Maps.reorder_layers/2` - Change layer order
- [ ] `Maps.toggle_layer_visibility/2` - Show/hide layer

#### Layer Concepts

**Default Layer:** Every map has at least one layer (created automatically).

**Event-Triggered Layers:** Layers can be linked to Flow Event nodes:
```
Event Node: "castle_burns" (in flow)
    ↓
Layer: "After the Fire" (on map)
    ↓
Pins: Show destroyed castle, remove market, add refugee camp
```

**Use Cases:**
- Before/after story events (castle burns, army arrives)
- Seasonal changes (winter/summer)
- Time of day (day/night)
- Quest progress (reveal hidden locations)

---

### 7.5.M.3 Map Pins

#### Database & Schema
- [ ] Create `map_pins` table (migration)
- [ ] Add indexes on `(map_id, layer_id)` and `(target_type, target_id)`

#### Context Functions
- [ ] `Maps.list_pins/2` - List pins for map (optionally filtered by layer)
- [ ] `Maps.create_pin/2` - Create new pin
- [ ] `Maps.update_pin/2` - Update pin position, target, style
- [ ] `Maps.delete_pin/1` - Delete pin
- [ ] `Maps.move_pin/3` - Update pin position (drag operation)

#### Pin Types

| Type      | Icon | Purpose                         | Target                |
|-----------|------|---------------------------------|-----------------------|
| location  | 📍   | Mark places                     | Page (location type)  |
| character | 👤   | Character home/current location | Page (character type) |
| event     | ⚡    | Story events                    | Flow                  |
| quest     | ❗    | Quest starts                    | Flow                  |
| portal    | 🚪   | Link to another map             | Map                   |
| custom    | 🔷   | User-defined                    | Any                   |

---

### 7.5.M.4 Map Connections (Optional)

Visual lines connecting pins (travel routes, relationships).

#### Database & Schema
- [ ] Create `map_connections` table (migration)

#### Context Functions
- [ ] `Maps.list_connections/1` - List connections for map
- [ ] `Maps.create_connection/2` - Create connection between pins
- [ ] `Maps.delete_connection/1` - Delete connection

---

### 7.5.M.5 Map Editor UI

Main interface for creating and editing maps.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ MAP EDITOR: Kingdom of Eldoria                    [Layers ▼] [Settings ⚙️]  │
├────────────────────────────────────────────────────────┬────────────────────┤
│                                                        │ PROPERTIES         │
│    ┌──────────────────────────────────────────────┐   │                    │
│    │                                              │   │ Selected: Capital  │
│    │         ⭐ Capital City                      │   │ Type: [Location ▼] │
│    │              │                               │   │ Icon: [📍]         │
│    │        ┌─────┴─────┐                         │   │ Color: [Blue ▼]    │
│    │        │           │                         │   │ Size: [Medium ▼]   │
│    │    📍 Village   📍 Port                      │   │                    │
│    │                                              │   │ Links to:          │
│    │                                              │   │ 📄 Capital City    │
│    │    👤 Jaime's House                          │   │ #loc.capital       │
│    │                                              │   │ [Change Target]    │
│    │              🏰 Castle                       │   │                    │
│    │                                              │   │ Tooltip:           │
│    │    [Background: world_map.png]               │   │ [The great capital]│
│    │                                              │   │                    │
│    └──────────────────────────────────────────────┘   │ Layer: [Default ▼] │
│                                                        │                    │
│ [Zoom: ─●─────] [Pan Mode] [Pin Mode 📍]              │ [Delete Pin]       │
├────────────────────────────────────────────────────────┴────────────────────┤
│ LAYERS                                                      [+ Add Layer]   │
│ [👁] Default          [👁] After the War (trigger: war_ends)               │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Implementation Tasks
- [ ] LiveView: `MapLive.Edit`
- [ ] Canvas component with pan/zoom (Leaflet.js or custom)
- [ ] Background image upload (reuse asset picker)
- [ ] Pin placement (click to place, drag to move)
- [ ] Pin selection and property editing
- [ ] Target selector (search pages/flows/maps)
- [ ] Layer toggle visibility
- [ ] Layer management panel

---

### 7.5.M.6 Map Viewer UI

Read-only view for navigating the map.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Kingdom of Eldoria                                            [Edit Mode]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │                                                                  │    │
│    │         ⭐ Capital City  ←── [Hover shows tooltip]               │    │
│    │              │                                                   │    │
│    │              │   ┌─────────────────────────┐                     │    │
│    │              │   │ 📍 Capital City         │                     │    │
│    │              │   │ The heart of the kingdom│                     │    │
│    │              │   │ [Open Page] [Start Flow]│  ← Click opens      │    │
│    │              │   └─────────────────────────┘                     │    │
│    │                                                                  │    │
│    │    👤 Jaime ←── [Click shows character popup]                    │    │
│    │                                                                  │    │
│    │              🚪 → [Click drills down to Castle map]              │    │
│    │                                                                  │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│ Layers: [Default ✓] [After War ○]                    [← Back to World Map] │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Implementation Tasks
- [ ] LiveView: `MapLive.Show`
- [ ] Read-only canvas with pan/zoom
- [ ] Pin hover tooltips
- [ ] Pin click → popup with actions
- [ ] Drill-down navigation (portal pins)
- [ ] Breadcrumb for map hierarchy
- [ ] Layer toggle for viewers

---

### 7.5.M.7 Maps Sidebar

Integration with project sidebar for navigation.

```
┌─────────────────────────┐
│ PROJECT SIDEBAR         │
├─────────────────────────┤
│ 📄 Pages                │
│ └── ...                 │
│                         │
│ 🔀 Flows                │
│ └── ...                 │
│                         │
│ 🗺️ Maps                 │  ← New section
│ ├── 🗺️ World Map        │
│ │   ├── 🗺️ North Kingdom│
│ │   └── 🗺️ South Empire │
│ └── 🗺️ Tavern Interior  │
│                         │
└─────────────────────────┘
```

#### Implementation Tasks
- [ ] Add "Maps" section to project sidebar
- [ ] Tree view for map hierarchy
- [ ] Context menu: New Map, Edit, Delete
- [ ] Drag to reorder

---

### 7.5.M.8 Page Integration

Link pages to maps and show map pins on pages.

#### Page → Map Link
- [ ] Add `map_id` field to pages table (optional FK)
- [ ] Add `map_pin_id` field to pages table (which pin represents this page)
- [ ] UI in page settings: "Show on map" selector

#### Backlinks on Pages
```
┌─────────────────────────────────────────────────────────────────┐
│ PAGE: Capital City                                              │
├─────────────────────────────────────────────────────────────────┤
│ [Content] [References]                                          │
├─────────────────────────────────────────────────────────────────┤
│ REFERENCES                                                      │
│                                                                 │
│ APPEARS ON MAPS                               ← New section     │
│ ├── 🗺️ World Map (pin: Capital City)         [View on Map →]   │
│ └── 🗺️ Northern Kingdom (pin: The Capital)   [View on Map →]   │
│                                                                 │
│ BACKLINKS                                                       │
│ └── ...                                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

### 7.5.M.9 Flow Event Integration

Connect Flow Event nodes to Map Layers.

#### Event → Layer Trigger
- [ ] Add event selector to layer configuration
- [ ] When event fires (in simulation/export), layer becomes active

#### UI in Layer Settings
```
┌─────────────────────────────────────────────────────────────────┐
│ LAYER SETTINGS: After the Fire                                  │
├─────────────────────────────────────────────────────────────────┤
│ Name: [After the Fire                    ]                      │
│                                                                 │
│ Trigger Event (optional):                                       │
│ [🎯 castle_burns              ▼]                                │
│  └── From: Act 1 / Siege / Attack Node                          │
│                                                                 │
│ When triggered:                                                 │
│ ○ Show this layer only                                          │
│ ● Add this layer to visible layers                              │
│ ○ Replace default layer                                         │
└─────────────────────────────────────────────────────────────────┘
```

#### Export Format
```json
{
  "maps": [
    {
      "id": "map-001",
      "shortcut": "maps.world",
      "layers": [
        {
          "id": "layer-001",
          "name": "Default",
          "is_default": true
        },
        {
          "id": "layer-002",
          "name": "After the Fire",
          "trigger_event": "castle_burns"
        }
      ],
      "pins": [...]
    }
  ]
}
```

---

## Database Migrations

### Migration 1: Maps

```elixir
create table(:maps) do
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  add :name, :string, null: false
  add :description, :text
  add :parent_map_id, references(:maps, on_delete: :nilify_all)
  add :background_asset_id, references(:assets, on_delete: :nilify_all)
  add :width, :integer
  add :height, :integer
  add :default_zoom, :float, default: 1.0
  add :default_center_x, :float, default: 50.0
  add :default_center_y, :float, default: 50.0
  add :shortcut, :string
  add :position, :integer, default: 0

  timestamps()
end

create unique_index(:maps, [:project_id, :shortcut],
  where: "shortcut IS NOT NULL",
  name: :maps_project_shortcut_unique)
create index(:maps, [:project_id, :parent_map_id])
```

### Migration 2: Map Layers

```elixir
create table(:map_layers) do
  add :map_id, references(:maps, on_delete: :delete_all), null: false
  add :name, :string, null: false
  add :is_default, :boolean, default: false
  add :trigger_event_id, :string  # References event node ID
  add :position, :integer, default: 0
  add :visible, :boolean, default: true

  timestamps()
end

create index(:map_layers, [:map_id, :position])
```

### Migration 3: Map Pins

```elixir
create table(:map_pins) do
  add :map_id, references(:maps, on_delete: :delete_all), null: false
  add :layer_id, references(:map_layers, on_delete: :nilify_all)
  add :position_x, :float, null: false
  add :position_y, :float, null: false
  add :pin_type, :string, default: "location"
  add :icon, :string
  add :color, :string
  add :label, :string
  add :target_type, :string
  add :target_id, :binary_id
  add :target_shortcut, :string
  add :tooltip, :text
  add :size, :string, default: "md"

  timestamps()
end

create index(:map_pins, [:map_id, :layer_id])
create index(:map_pins, [:target_type, :target_id])
```

### Migration 4: Map Connections (Optional)

```elixir
create table(:map_connections) do
  add :map_id, references(:maps, on_delete: :delete_all), null: false
  add :from_pin_id, references(:map_pins, on_delete: :delete_all), null: false
  add :to_pin_id, references(:map_pins, on_delete: :delete_all), null: false
  add :line_style, :string, default: "solid"
  add :color, :string
  add :label, :string
  add :bidirectional, :boolean, default: true

  timestamps()
end

create index(:map_connections, [:map_id])
```

### Migration 5: Page Map Link

```elixir
alter table(:pages) do
  add :map_id, references(:maps, on_delete: :nilify_all)
  add :map_pin_id, references(:map_pins, on_delete: :nilify_all)
end
```

---

## Implementation Order

| Order   | Task                                   | Dependencies         | Testable Outcome           |
|---------|----------------------------------------|----------------------|----------------------------|
| 1       | Maps table + CRUD                      | None                 | Can create maps            |
| 2       | Map layers table + CRUD                | Task 1               | Can add layers             |
| 3       | Map pins table + CRUD                  | Task 2               | Can add pins               |
| 4       | Basic map editor (canvas + background) | Task 1, Assets       | Can upload map image       |
| 5       | Pin placement UI                       | Task 3-4             | Can place pins on map      |
| 6       | Pin property editor                    | Task 5               | Can configure pins         |
| 7       | Target selector (link to pages/flows)  | Task 6, Pages, Flows | Pins link to content       |
| 8       | Map viewer (read-only)                 | Task 5               | Can navigate map           |
| 9       | Maps sidebar section                   | Task 1               | Maps in navigation         |
| 10      | Map hierarchy (parent/child)           | Task 1               | Can drill down             |
| 11      | Layer visibility toggle                | Task 2               | Can show/hide layers       |
| 12      | Page backlinks for maps                | Task 7               | Pages show map appearances |
| 13      | Event → Layer trigger                  | Task 2, Flows        | Events change layers       |
| 14      | Map connections (optional)             | Task 3               | Can draw routes            |

---

## Technical Considerations

### Canvas Implementation Options

**Option A: Leaflet.js**
- Pros: Battle-tested, great pan/zoom, mobile support
- Cons: Designed for geo maps, some overhead
- Use: Set CRS to simple, use image overlay

**Option B: Konva.js / Fabric.js**
- Pros: More control, canvas-native
- Cons: More work for pan/zoom
- Use: Good if we need complex shapes

**Option C: Custom SVG + CSS transforms**
- Pros: Lightweight, no dependencies
- Cons: More work, edge cases
- Use: Simple use cases only

**Recommendation:** Leaflet.js with simple CRS - proven, well-documented, handles all the hard parts.

### Responsive Pin Positioning

Store positions as percentages (0-100) not pixels:
```elixir
position_x: 45.5  # 45.5% from left
position_y: 30.0  # 30% from top
```

This allows maps to work at any size/zoom level.

### Performance

- Lazy load pins when map is opened
- Virtualize pin list if > 100 pins
- Use asset thumbnails for map backgrounds
- Cache layer visibility state in localStorage

---

## Testing Strategy

### Unit Tests
- [ ] Map CRUD operations
- [ ] Pin position validation (0-100 range)
- [ ] Layer default enforcement (exactly one default)
- [ ] Target link validation

### Integration Tests
- [ ] Create map with background image
- [ ] Add pins and link to pages
- [ ] Layer visibility toggle
- [ ] Drill-down navigation

### E2E Tests
- [ ] Full map creation workflow
- [ ] Pin placement and linking
- [ ] Navigate via map to page/flow

---

## Open Questions

1. **Multiple pins per page?** Can a character appear on multiple maps?
   - Recommendation: Yes, pages can be linked from multiple pins

2. **Pin clustering?** What happens when many pins overlap at low zoom?
   - Recommendation: Defer - not critical for MVP

3. **Real-time collaboration?** Should map editing be collaborative?
   - Recommendation: Defer - single editor for now, view is fine

4. **Mini-map on pages?** Show small map preview on location pages?
   - Recommendation: Nice-to-have, defer to later

---

## Success Criteria

- [ ] Can create maps and upload background images
- [ ] Can place pins and link them to Pages/Flows
- [ ] Can navigate world via interactive map
- [ ] Layers work for different map states
- [ ] Map hierarchy allows drill-down (world → region → city)
- [ ] Pages show which maps they appear on
- [ ] Event nodes can trigger layer changes
- [ ] Maps export in JSON for game engines

---

## Comparison: World Anvil vs Storyarn

| Feature              | World Anvil           | Storyarn                |
|----------------------|-----------------------|-------------------------|
| Interactive maps     | Yes (pins, labels)    | Yes                     |
| Link to articles     | Yes                   | Yes (pages + flows)     |
| Layer system         | Basic                 | Event-triggered         |
| Map hierarchy        | No (flat)             | Yes (drill-down)        |
| Map creation         | External only         | External (upload image) |
| Timeline integration | Chronicles (separate) | Via Flow Events         |
| Collaboration        | View only             | Edit (future)           |

**Key Advantages:**
- Event-triggered layers = dynamic storytelling
- Direct Flow integration = maps are part of narrative
- Hierarchy for scale (world → building)

---

## Future Enhancements (Not in Scope)

- **Map drawing tools** - Draw shapes, regions, roads directly
- **Fog of war** - Reveal areas as players explore
- **Animated pins** - Pins that move along paths
- **Heat maps** - Visualize where story events cluster
- **3D maps** - Isometric or 3D building interiors

---

*This phase enhances world visualization and integrates with the Flow Event system from PHASE_7_5_FLOWS_ENHANCEMENT.md.*
