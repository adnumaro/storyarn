# Phase 2: Scene Editor V2 — Full Vue Migration

## Goal
Create a complete Vue-based scene editor at `/v2/.../scenes/:id` with Leaflet canvas, floating toolbars, dock, sidebars, and all element interactions. Zero HEEx in the editor area.

## Prerequisites
- [ ] Phase 1 complete (all base components, NuxtUI, Storybook)
- [ ] Leaflet Vue plugin evaluated and chosen

## 2.1 Route & LiveView Shell

### Route
```elixir
# In router.ex, inside authenticated scope
live "/v2/workspaces/:workspace_slug/projects/:project_slug/scenes/:id",
     SceneLive.ShowV2, :show
```

### LiveView (`scene_live/show_v2.ex`)
Thin shell — loads data, passes to Vue, handles events:
```elixir
def render(assigns) do
  ~H"""
  <.vue
    v-component="SceneEditor"
    v-socket={@socket}
    id="scene-editor"
    scene={@scene}
    layers={@layers}
    pins={@pins}
    zones={@zones}
    connections={@connections}
    annotations={@annotations}
    project={@project}
    workspace={@workspace}
    project_sheets={@flat_sheets}
    project_flows={@flat_flows}
    project_scenes={@flat_scenes}
    project_variables={@project_variables}
    can_edit={@can_edit}
    current_user={@current_user}
    online_users={@online_users}
  />
  """
end
```

All `handle_event` clauses from current `show.ex` are preserved (copy as-is). The LiveView is a data gateway — Vue handles all UI.

## 2.2 Leaflet Vue Integration

### Package
```bash
npm install @vue-leaflet/vue-leaflet leaflet
```

### Canvas Component (`SceneCanvas.vue`)
- Replaces the current `scene_canvas.js` hook (506 lines)
- Uses `<LMap>`, `<LImageOverlay>`, `<LMarker>`, `<LPolygon>`, `<LPolyline>`
- Custom marker component for pins with avatar/icon rendering
- Zone polygons with edit handles
- Connection polylines with decorators
- Annotation text overlays

### Canvas Features to Port
| Feature | Current (JS hook) | Vue Implementation |
|---------|-------------------|-------------------|
| Background image | `L.imageOverlay` | `<LImageOverlay :url="scene.background_url">` |
| Pin markers | Custom `L.divIcon` | `<PinMarker>` Vue component with avatar |
| Zone polygons | `L.polygon` with edit | `<ZonePolygon>` with vertex editing |
| Connections | `L.polyline` + decorator | `<ConnectionLine>` with arrow markers |
| Annotations | `L.divIcon` with text | `<AnnotationOverlay>` |
| Drag pins | `L.marker.dragging` | `@dragend` event on `<LMarker>` |
| Click to create | Map click handler | `@click` on `<LMap>` |
| Zoom/pan | Leaflet native | Leaflet native (unchanged) |
| Cursor sharing | Custom hook | `useCursorSharing()` composable |

## 2.3 Layout Components

### SceneEditor.vue (Root)
```
┌─────────────────────────────────────────────────┐
│ SceneHeader (breadcrumb, title, shortcuts)       │
├─────────────────────────────────────────────────┤
│ ┌─────────┐                     ┌─────────────┐ │
│ │TreePanel│   SceneCanvas       │ElementPanel │ │
│ │(scenes, │   (Leaflet map)     │(pin/zone    │ │
│ │layers)  │                     │properties)  │ │
│ │         │                     │             │ │
│ └─────────┘                     └─────────────┘ │
│             ┌───────────────┐                    │
│             │   Dock        │                    │
│             │ (tools bar)   │                    │
│             └───────────────┘                    │
│ ┌───────────────────────────────────────────────┐│
│ │ FloatingToolbar (per-element, on hover/select)││
│ └───────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
```

### Vue Components
| Component | Purpose | NuxtUI Base |
|-----------|---------|------------|
| `SceneEditor.vue` | Root layout, panel management | custom |
| `SceneHeader.vue` | Breadcrumb, title, export, draft | SButton, EditableText |
| `SceneCanvas.vue` | Leaflet map container | vue-leaflet |
| `PinMarker.vue` | Pin rendering with avatar/icon | custom Leaflet marker |
| `ZonePolygon.vue` | Zone with vertex editing | custom Leaflet polygon |
| `ConnectionLine.vue` | Connection polyline | custom Leaflet polyline |
| `AnnotationOverlay.vue` | Text annotation | custom Leaflet div overlay |
| `Dock.vue` | Bottom toolbar (create pin, layers, lock) | SToolbar |
| `LayerBar.vue` | Layer visibility toggles | SToggle, SDropdown |
| `TreePanel.vue` | Scene/layer tree navigation | STree, SSidebar |
| `ElementPanel.vue` | Selected element properties | SSidebar |
| `PinPanel.vue` | Pin properties form | SSelect, SInput, SToggle, ConditionBuilder |
| `ZonePanel.vue` | Zone properties form | SSelect, SInput, SToggle, ConditionBuilder, InstructionBuilder |
| `ConnectionPanel.vue` | Connection properties | SButton |
| `AnnotationPanel.vue` | Annotation text editing | STextarea |
| `SceneSettingsPanel.vue` | Background, display mode, scale, ambient flows | SSelect, SInput, SSlider |
| `FloatingToolbar.vue` | Per-element actions (on hover) | SToolbar, SPopover |
| `PinToolbar.vue` | Pin-specific toolbar (label, color, size, lock, delete) | SInput, ColorPicker, SDropdown |
| `ZoneToolbar.vue` | Zone-specific toolbar (name, color, walkable, delete) | same |
| `ExplorationPlayer.vue` | Exploration preview mode | custom (port exploration_player.js) |

## 2.4 Event Handlers (LiveView Side)

Copy ALL `handle_event` clauses from current `show.ex` to `show_v2.ex`. The events stay identical — Vue pushes the same event names with same payloads. The handlers:

### Pin Events
- `create_pin`, `update_pin`, `delete_pin`, `move_pin`
- `update_pin_condition`, `update_pin_condition_effect`
- `set_pending_delete_pin`, `confirm_delete_element`
- `toggle_pin_icon_upload`, `upload_pin_icon`

### Zone Events
- `create_zone`, `update_zone`, `delete_zone`
- `update_zone_vertices`, `update_zone_assignments`
- `update_zone_condition`, `update_zone_condition_effect`

### Connection Events
- `create_connection`, `delete_connection`
- `clear_connection_waypoints`, `update_connection_waypoints`

### Annotation Events
- `create_annotation`, `update_annotation`, `delete_annotation`

### Canvas Events
- `update_viewport`, `cursor_moved`, `cursor_left`

### Settings Events
- `update_scene_settings`, `remove_background`, `upload_background`
- `update_exploration_display_mode`, `update_scene_scale`
- `toggle_ambient_flow`, `add_ambient_flow`, `remove_ambient_flow`
- `update_ambient_flow_trigger`, `update_ambient_flow_priority`

### UI State Events
- `select_element`, `deselect_element`
- `open_element_panel`, `close_element_panel`
- `open_scene_settings`, `close_scene_settings`
- `toggle_layer`, `rename_layer`, `reorder_layers`

## 2.5 Collaboration

### Composables
- `useCursorSharing(sceneId)` — sends cursor position, renders other users' cursors
- `usePresence(scope)` — tracks online users, shows avatars
- `useLocking(scope)` — element locking for concurrent editing

### PubSub Integration
Vue receives server pushes via LiveVue's reactive props:
- `online_users` prop updates when presence changes
- `pins`, `zones`, `connections` props update when other users make changes
- Element locks shown as badges on locked elements

## Deliverables
- [ ] `/v2/.../scenes/:id` route working
- [ ] Full Leaflet canvas with pins, zones, connections, annotations
- [ ] All toolbars (dock, floating per-element)
- [ ] Element panel (pin/zone/connection properties)
- [ ] Scene settings panel
- [ ] Layer management
- [ ] Exploration player (preview mode)
- [ ] Collaboration (cursors, presence, locks)
- [ ] All events connected to LiveView handlers
- [ ] Feature parity with current scene editor

## Estimated Scope
~25 Vue components + canvas integration + all event wiring
