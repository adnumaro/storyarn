%{
  title: "Scenes Overview",
  category_label: "Scene Design",
  order: 1,
  description: "Map your world with spatial canvases, zones, pins, and connections."
}
---

Scenes are **spatial canvases** for mapping your game world. They let you lay out locations, define areas of interest, and create connections between places — giving your narrative a physical dimension.

## When to use Scenes

- **World maps** — continent, region, or city layouts
- **Level design outlines** — room layouts with connections
- **Location hierarchies** — tavern floor plan with interactive zones
- **Exploration maps** — player-navigable areas with points of interest

## Core concepts

### Layers

Scenes support multiple **layers** for organizing visual elements:

- **Background layer** — a base image (map, blueprint, concept art)
- **Content layers** — where you place zones and pins
- Toggle layer visibility for different views of the same scene

### Zones

Zones are **interactive regions** on the canvas:

- Draw them over areas of your map
- Each zone can link to a flow, a sheet, or another scene
- Zones can have conditions (only accessible if a variable is true)
- Zones can have actions (modify variables when entered)

### Pins

Pins are **point markers** for specific locations:

- NPCs, items, doors, quest markers
- Each pin can have a label, icon, and linked content
- Lighter than zones — use them for individual points of interest

### Connections

Draw **connections** between zones to define navigation paths:

- Show how the player moves between areas
- Connections can be one-way or bidirectional
- Connections can have conditions (locked door, quest prerequisite)

## Exploration mode

Switch to **Exploration mode** to navigate your scene as a player would — clicking zones to move between areas, seeing which connections are available, and testing the spatial flow of your game world.

## Annotations

Add **annotations** directly on the canvas for design notes, reminders, or feedback — visible to your team but separate from the game content.
