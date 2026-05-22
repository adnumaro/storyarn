%{
title: "Scenes Overview",
category_label: "Scene Design",
order: 1,
description: "Map your world with spatial canvases, zones, pins, connections, layers, and exploration."
}

---

Scenes are spatial canvases for mapping a project's world. Use them for world maps, level layouts, location hierarchies, interactive exploration maps, and narrative spaces that need more than a linear flow graph.

<div class="docs-alert docs-alert-warning">
  <svg class="docs-alert-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.46 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>
  <p><strong>Documentation in progress.</strong> Scenes have several connected systems. This section breaks them into focused pages so each concept is easier to follow.</p>
</div>

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Full scene editor canvas with a background map, zones, pins, routes, layers panel, and bottom toolbar
</div>

## Core pieces

| Piece | What it does | Read next |
| ----- | ------------ | --------- |
| **Zones** | Polygonal areas on the canvas. Use them for rooms, regions, interactable areas, child-scene drill-downs, and conditional access. | [Zones and Interactive Areas](/docs/scene-design/zones) |
| **Pins** | Point markers for locations, characters, events, objects, or custom map references. | [Pins](/docs/scene-design/pins) |
| **Connections** | Lines between pins. Use them for paths, routes, travel links, or relationships. | [Connections and Routes](/docs/scene-design/connections-routes) |
| **Layers** | Visibility groups for organizing canvas elements and controlling fog of war. | [Layers and Visibility](/docs/scene-design/layers-visibility) |
| **Exploration** | A fullscreen player-like mode that evaluates actions, conditions, and flow overlays. | [Actions, Conditions, and Exploration](/docs/scene-design/actions-conditions-exploration) |

## When to use scenes

- **World maps** -- continents, regions, towns, or dungeon maps.
- **Level design outlines** -- room layouts with navigable connections.
- **Location hierarchies** -- drill down from a world map into regions, buildings, or rooms.
- **Interactive exploration** -- let users click map elements, evaluate conditions, change variables, and trigger flows.

## Editor model

Scenes use percentage-based coordinates, so elements stay aligned as the canvas scales. The editor has a bottom dock for drawing and selection tools, a side panel for advanced properties, and a tree/sidebar structure for organizing scenes.

Each scene can have a background image, shortcut, scale settings for measurement, child scenes, layers, and exported PNG/SVG snapshots.
