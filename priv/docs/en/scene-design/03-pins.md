%{
title: "Pins",
category_label: "Scene Design",
order: 3,
description: "Place point markers for characters, locations, events, sheets, flows, scenes, and external references."
}

---

Pins are point markers placed on a scene. Use them for exact locations: a character position, a quest object, a travel point, a landmark, an event, or a custom note.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Scene canvas with location, character, event, and custom pins using different colors and sizes
</div>

## Pin types

| Type | Typical use |
| ---- | ----------- |
| **Location** | Places, landmarks, doors, exits, map labels |
| **Character** | NPCs, party members, enemies, social encounters |
| **Event** | Timed events, quest beats, triggers |
| **Custom** | Project-specific marker types |

## Creating pins

Create a free pin from the dock, or create a pin from a sheet when the marker should point to an existing character, item, location, or world entity.

Sheet-linked pins make the map easier to keep connected to world data. They also make it clearer which scene elements represent which structured records.

## Targets

Pins can link to:

- A sheet
- A flow
- Another scene
- An external URL

This makes pins useful both as map markers and as navigation points into the rest of the project.

## Appearance

Pins can define label, type, size, color, icon, custom icon asset, layer, and lock state. Use size and color consistently so users can scan a scene without opening every pin.

## Runtime behavior

Like zones, pins can use actions and conditions. A pin can trigger a flow, display a variable, run an instruction, hide until a condition is true, or appear disabled when interaction is blocked.
