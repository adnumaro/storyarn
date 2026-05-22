%{
title: "Connections and Routes",
category_label: "Scene Design",
order: 4,
description: "Connect pins with paths, labels, direction, line styles, and waypoint editing."
}

---

Connections are visual lines between pins. Use them to show routes, paths, travel links, relationships, quest dependencies, or any association that benefits from being visible on the scene.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Scene map with several pins connected by solid, dashed, and waypointed route lines
</div>

## Creating connections

Use the connector tool, then choose a source pin and a target pin. Connections always attach to pins, which keeps route endpoints stable as pins move.

## Direction

Connections can be bidirectional or one-way.

| Direction | Meaning |
| --------- | ------- |
| **Bidirectional** | Travel or relationship works both ways. |
| **One-way** | Movement, dependency, or relationship has a single direction. |

## Styling

Connections can define line color, width, style, and label visibility. Use visual differences intentionally:

- Solid lines for normal routes.
- Dashed lines for conditional, hidden, or indirect routes.
- Dotted lines for relationships or non-physical links.

## Waypoints

Waypoints let you bend a connection around map features. Add intermediate points when a route should follow a road, corridor, coastline, or design path instead of drawing a straight line.

Keep routes readable. Too many waypoints can make editing harder; use enough to communicate the path and no more.

## What connections do not do

Connections are visual and structural. Runtime interaction usually belongs to the connected pins or zones. If a route should become locked, hidden, or trigger state changes, model that behavior with conditions/actions on the relevant scene elements.
