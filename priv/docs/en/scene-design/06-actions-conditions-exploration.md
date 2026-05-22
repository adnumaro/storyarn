%{
title: "Actions, Conditions, and Exploration",
category_label: "Scene Design",
order: 6,
description: "Make scene elements interactive with variable checks, instructions, display actions, flow overlays, and exploration mode."
}

---

Scenes can be more than static maps. Zones and pins can evaluate conditions, run instructions, display variable values, navigate to scenes, and trigger flows during exploration.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Exploration mode showing an interactive map with a highlighted zone and a flow dialogue overlay
</div>

## Actions

| Action | Behavior |
| ------ | -------- |
| **None** | The element has no runtime action. |
| **Instruction** | Runs variable assignments using the shared [Instruction Editor](/docs/narrative-design/instruction-editor). |
| **Display** | Shows the current value of a variable. |
| **Flow target** | Opens a flow overlay on top of the scene. |
| **Scene target** | Navigates to another scene, often a child scene. |

## Conditions

Attach a condition to a zone or pin when its availability depends on game state. Scene conditions use the shared [Condition Editor](/docs/narrative-design/condition-editor).

When the condition is false, the element can:

- **Hide** -- it disappears from the exploration view.
- **Disable** -- it remains visible but cannot be interacted with.

Use this for locked doors, hidden NPCs, quest-gated areas, revealable routes, or conditional events.

## Exploration mode

Exploration mode is a fullscreen player-like simulation of the scene. It evaluates actions and conditions in real time.

During exploration, users can:

1. Click zones and pins.
2. Trigger flows without leaving the scene.
3. Navigate to child scenes.
4. Run instructions that update variables.
5. Display variable values.
6. See elements hide or disable based on conditions.

## Flow overlays

When a scene element targets a flow, the scene dims and the flow appears as an overlay. The player completes the dialogue or branch, then returns to the map with any variable changes applied.

This is the main bridge between spatial design and narrative logic: a place on the map can start a conversation, modify state, and reveal or disable other map elements.

## Testing interactions

Use exploration mode to validate scene logic before exporting or handing the map to collaborators. Check that conditions evaluate as expected, instructions update the right variables, and flow overlays return to the correct scene state.
