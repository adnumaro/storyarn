%{
  title: "Scenes Overview",
  category_label: "Scene Design",
  order: 1,
  description: "Map your world with spatial canvases, zones, pins, and connections."
}
---

Scenes are **spatial canvases** for mapping your game world. Built on a Leaflet.js canvas with full pan, zoom, and minimap support, they let you lay out locations, define interactive areas, draw connections between places, and -- uniquely -- explore the result as a player would.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The scene editor canvas showing a world map with zones, pins, connections, and the bottom dock toolbar
</div>

## When to use Scenes

- **World maps** -- continent, region, or city layouts with a background image
- **Level design outlines** -- room layouts with navigable connections between areas
- **Location hierarchies** -- drill down from a tavern floor plan into individual rooms
- **Interactive exploration maps** -- player-navigable areas with variable-driven visibility and actions

## Canvas elements

### Zones

Zones are **polygonal regions** drawn on the canvas. Vertices are stored as percentage coordinates (0--100) relative to the scene dimensions, so they scale with any background image.

- **Shapes** -- draw zones as rectangles, triangles, circles, or freeform polygons
- **Styling** -- fill color, border color, border width, border style (solid, dashed, dotted), and opacity
- **Targets** -- link a zone to a flow or another scene (for drill-down navigation)
- **Actions** -- `none`, `instruction` (execute variable assignments when entered), or `display` (show a variable value)
- **Conditions** -- hide or disable a zone based on variable conditions, using the same condition builder as flows
- **Tooltips** -- hover text for additional context
- **Locking** -- lock a zone to prevent accidental edits

### Pins

Pins are **point markers** for specific locations. They support four types: `location`, `character`, `event`, and `custom`.

- **Sizes** -- small, medium, or large
- **Targets** -- link to a sheet, flow, scene, or external URL
- **Sheet binding** -- create a pin directly from a sheet (characters, items) to auto-link it
- **Actions and conditions** -- same system as zones (`instruction`, `display`, `hide`, `disable`)
- **Custom icons** -- use any icon name or upload a custom icon asset
- **Connections** -- pins serve as endpoints for scene connections

### Connections

Connections are **visual lines between two pins**, representing paths, routes, or relationships.

- **Direction** -- bidirectional (default) or one-way
- **Styling** -- line style (solid, dashed, dotted), line width, and color
- **Labels** -- optional text label with show/hide toggle
- **Waypoints** -- add intermediate points to curve a connection path (up to 50 waypoints)

### Annotations

Annotations are **text labels** placed directly on the canvas for design notes, reminders, or team feedback.

- **Font sizes** -- small, medium, or large
- **Colors** -- customizable text color
- **Locking** -- lock to prevent accidental moves

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Close-up of canvas elements: a styled zone with tooltip, a character pin linked to a sheet, a dashed connection with label, and an annotation
</div>

## Layers

Scenes support multiple **layers** for organizing content. Every scene starts with a default layer.

- **Visibility toggle** -- show or hide layers independently to view different aspects of the same scene
- **Layer assignment** -- every zone, pin, and annotation belongs to a layer
- **{accent}Fog of war{/accent}** -- enable per-layer fog with customizable color and opacity, covering unexplored areas until the player reaches them

## Drawing tools

The bottom dock provides **10 tools** organized into groups:

| Group | Tools | Purpose |
|-------|-------|---------|
| **Navigation** | Select, Pan | Select elements or pan around the canvas |
| **Zone shapes** | Rectangle, Triangle, Circle, Freeform | Draw polygonal zones on the canvas |
| **Elements** | Free Pin, From Sheet Pin | Place point markers (free or linked to a sheet) |
| **Text** | Annotation | Add text notes directly on the canvas |
| **Linking** | Connector | Draw connections between two pins |
| **Measure** | Ruler | Measure distances between two points |

The editor switches between **Edit mode** (dock visible, elements editable) and **View mode** (read-only, clean canvas).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The bottom dock toolbar showing all tool groups: Select, Pan, Zone Shapes dropdown, Pin dropdown, Annotation, Connector, and Ruler
</div>

## {accent}Zone drill-down{/accent}

Double-click a zone to **drill into it as a child scene**. Storyarn automatically:

1. Crops the parent scene's background image to the zone's bounding box
2. Upscales the cropped region to a minimum of 1000px (with sharpening) so detail is preserved even at deep zoom levels
3. Creates a new child scene with the extracted image as its background
4. Normalizes the zone's vertices into the child scene's coordinate space

This lets you build **location hierarchies** naturally -- a world map with continent zones, each continent drilling down to a regional map, each region to a city, each city to a building floor plan. Every level has its own zones, pins, connections, and layers.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Drill-down sequence: world map with a highlighted zone, then the child scene showing the cropped and upscaled region with its own zones and pins
</div>

## Actions and conditions

Both zones and pins support **actions** and **conditions** that tie spatial elements to your variable system.

### Actions

| Action type | Behavior |
|-------------|----------|
| **None** | No action (default) |
| **Instruction** | Execute variable assignments when the element is clicked. Uses the same assignment builder as flow instruction nodes. |
| **Display** | Show a variable's current value on the element. References a variable by its full path (e.g., `mc.jaime.health`). |

### Conditions

Attach a condition to any zone or pin using the condition builder. When the condition evaluates to false:

- **Hide** (default) -- the element is removed from the canvas entirely
- **Disable** -- the element remains visible but cannot be interacted with

This lets you create locked doors that unlock when a quest flag is set, NPCs that appear only after a story event, or areas that become accessible based on player progress.

## {accent}Exploration Mode{/accent}

**No other narrative design tool does this.**

Exploration Mode is a **fullscreen immersive experience** that lets you navigate your scene as a player would. It is not a preview -- it is a live simulation of your spatial narrative.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Exploration Mode showing the fullscreen map with interactive zones highlighted, the toolbar at top, and the zone visibility toggle
</div>

### How it works

1. **Launch** Exploration Mode from the scene header.
2. **Navigate** by clicking zones and pins on the map. Conditions are evaluated in real time -- hidden elements disappear, disabled elements are grayed out.
3. **Execute actions** -- clicking an instruction zone or pin modifies variables immediately. Clicking a display element shows the variable value.
4. **Trigger flows** -- clicking a zone or pin linked to a flow opens a **flow dialogue overlay** on a dimmed map background. The flow plays in-place (no URL change), including full cross-flow jumps and returns via the engine call stack.
5. **Navigate scenes** -- clicking a zone linked to another scene navigates to that child scene seamlessly.
6. **Variable state persists** across interactions within the same exploration session.
7. **Toggle zone visibility** with the toolbar button to see or hide zone boundaries.
8. **Keyboard controls** -- use keyboard shortcuts to navigate and interact.

### Flow overlay

When a flow is triggered during exploration, the map dims and the flow dialogue appears as an overlay. You see the same slide-based player experience as the Story Player, complete with dialogue text, speaker info, and player choices. When the flow completes, you return to the map with any variable changes applied.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Exploration Mode with a flow overlay: the map is dimmed in the background, and a dialogue slide with player choices is shown in the center
</div>

## Floating toolbar

When you select an element on the canvas, a **FigJam-style floating toolbar** appears above it with quick-edit controls specific to that element type:

- **Zones** -- fill color, opacity, border style, border color, layer picker, lock toggle, drill-down button
- **Pins** -- label, pin type selector, color, size, layer picker, lock toggle
- **Connections** -- line style, color, label, direction toggle
- **Annotations** -- text, font size, color, lock toggle

Advanced properties like targets, conditions, and actions are edited in the **side panel** that opens when you select an element.

## Export

Export any scene to **PNG** or **SVG** format directly from the scene header. The export captures the current canvas view including all visible layers, zones, pins, connections, and annotations.

## Scene organization

Like all Storyarn entities, scenes support a **tree structure** in the sidebar. This tree reflects both manual organization and drill-down hierarchies -- zones that drill into child scenes create parent-child relationships automatically.

Each scene has a **shortcut** (e.g., `world-map`) for cross-referencing, and an optional **scale** with custom unit and value for the ruler tool.
