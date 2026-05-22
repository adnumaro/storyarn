%{
title: "Layers and Visibility",
category_label: "Scene Design",
order: 5,
description: "Organize scene elements into layers and control visibility, editing, and fog of war."
}

---

Layers group scene elements so you can organize dense maps. Use them to separate regions, encounter information, character positions, design notes, travel routes, spoilers, or exploration state.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Scene layers panel showing several named layers with visibility toggles and fog of war settings
</div>

## Layer assignment

Zones, pins, and annotations belong to a layer. Assign elements as you create them, or move them later from the element panel.

Connections are usually read in context with their pins. Keep route and pin layers aligned unless you have a clear reason to separate them.

## Visibility toggles

Turn layers on or off to focus the editor. This is useful when a scene has multiple design concerns:

- World geography
- Quest routes
- NPC positions
- Hidden interactions
- Designer notes
- Review annotations

## Fog of war

Layers can enable fog of war with custom color and opacity. Use this for player-facing exploration, hidden areas, or progressive reveal designs.

Fog belongs to the layer, not to a single element. Put related revealable content into the same layer when it should share fog behavior.

## Editing safely

Use layers with lock states and element locks to avoid accidental edits. For large scenes, a practical workflow is:

1. Create background and main zones.
2. Lock stable geography.
3. Add pins and routes on separate layers.
4. Add conditional/exploration elements last.
