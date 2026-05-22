%{
title: "Zones and Interactive Areas",
category_label: "Scene Design",
order: 2,
description: "Draw areas on a scene, style them, link them, and use them for drill-down navigation."
}

---

Zones are polygonal regions drawn on a scene. They can represent rooms, districts, terrain areas, encounter regions, doors, hidden areas, or any part of a map that should behave as an interactive area.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Scene canvas showing several styled zones: a room rectangle, a freeform region, and a highlighted drill-down zone
</div>

## Drawing zones

The bottom dock includes zone tools for common shapes:

| Tool | Use it for |
| ---- | ---------- |
| **Rectangle** | Rooms, buildings, UI-like map panels |
| **Triangle** | Directional markers, landmarks, map wedges |
| **Circle** | Areas of influence, radius-like regions, camps |
| **Freeform** | Irregular rooms, regions, paths, terrain boundaries |

Zone vertices are stored as percentages relative to the scene dimensions. This keeps zones aligned if the background image or viewport size changes.

## Editing vertices

Double-click a zone to edit its vertices. Drag handles to reshape the area, then confirm the change. Use this when a rough zone needs to follow the map artwork more closely.

## Styling and visibility

Zones can define fill color, border color, border width, border style, opacity, tooltip text, layer assignment, and lock state. Lock zones that should not move while you are editing pins or connections around them.

## Targets and drill-down

A zone can link to another scene. Double-clicking a zone can also create a child scene from that area: Storyarn crops the parent background around the zone, upscales the image when needed, and creates the child scene with normalized coordinates.

Use this for location hierarchies:

```text
World map -> Region -> Town -> Building -> Room
```

## Actions and conditions

Zones can run instructions, display variables, hide, or disable themselves based on conditions. See [Actions, Conditions, and Exploration](/docs/scene-design/actions-conditions-exploration) for the runtime behavior.
