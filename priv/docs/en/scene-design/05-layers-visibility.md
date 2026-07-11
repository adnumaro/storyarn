%{
title: "Layers and Visibility",
category_label: "Scene Design",
order: 5,
description: "Organize scene elements into layers and control visibility and fog overlays."
}

---

Layers group scene elements so you can organize dense scenes. Use them to separate regions, encounter information, character positions, design notes, travel routes, spoilers, or exploration areas.

<img src="/images/docs/scenes-layers.png" alt="Scene layers panel showing several named layers with visibility toggles and access to fog design" loading="lazy">

## Layer assignment

Zones, pins, and annotations belong to a layer. Assign elements as you create them, or move them later from the element panel.

Connections are read in context with the points they connect. If a scene has many routes, use clear layer names to organize the pins, zones, and annotations that help explain them.

## Visibility toggles

Turn layers on or off to focus the editor. This toggle helps while editing the scene; it does not replace the rules, conditions, or exploration settings that determine what the player sees.

- World geography
- Quest routes
- NPC positions
- Hidden interactions
- Designer notes
- Review annotations

## Fog overlay

A layer can be marked as revealed above fog. The overlay color and opacity are configured once from the scene settings, and apply to the whole scene when at least one layer has this option enabled.

When fog is active, the scene is covered by the overlay and the content of the revealed layers is drawn again above it. This works with pins, zones, and annotations in those layers. Connections are drawn above the overlay when they connect to pins in a revealed layer.

This setting does not store player exploration progress or reveal areas automatically. To control when an element appears in exploration mode, use that element's conditions.

## Editing safely

Use layers with lock states and element locks to avoid accidental edits. For large scenes, a practical workflow is:

1. Create background and main zones.
2. Lock stable geography.
3. Add pins and routes on separate layers.
4. Add conditional/exploration elements last.
