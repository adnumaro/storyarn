%{
title: "Actions, Conditions, and Exploration",
category_label: "Scene Design",
order: 6,
description: "Make scene elements interactive with conditions, actions, displays, collections, flows on top of scenes, and exploration mode."
}

---

Scenes can be more than static maps. Zones handle area actions: running instructions, displaying values, navigating to scenes, or launching flows. Pins represent specific points and can launch a flow, move as playable characters or patrols, and evaluate visibility rules during exploration.

<img src="/images/docs/scenes-exploration-current.png" alt="Exploration mode showing an interactive map with pins and player controls" loading="lazy">

## Interaction types

| Type                       | Behavior                                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------------------- |
| **Action**                 | Runs instructions, navigates to a scene or flow, or combines both.                                 |
| **Walkable Area**          | Marks where the player can move in exploration mode.                                               |
| **Display**                | Shows a variable on the map, either as value only or name + value.                                 |
| **Collection**             | Opens a collection window with collectible items, each with optional conditions and instructions.  |
| **Pin with flow**          | Launches the pin's flow on top of the scene.                                                       |
| **Playable or patrol pin** | Lets users control a character inside walkable areas or move a non-playable pin along connections. |

Action zones are the primary type for interactive behavior. Use them when part of the map should open a scene, launch a flow, or change variables.

## Conditions

Attach a condition to a zone or pin when its availability depends on game state. Scene conditions use the shared [Condition Editor](/docs/narrative-design/condition-editor).

When the condition is false, the element can:

- **Hide** -- it disappears from the exploration view.
- **Disable** -- it remains visible, but is locked.

Use this for locked doors, hidden NPCs, quest-gated areas, revealable routes, or conditional events.

## Exploration mode

Exploration mode is a fullscreen player-like simulation of the scene. It evaluates actions and conditions in real time.

During exploration, users can:

1. Click interactive zones and pins with a flow.
2. Trigger flows without leaving the scene.
3. Navigate to child scenes from Action zones.
4. Run instructions from Action or Collection zones.
5. Display variable values with Display zones.
6. Open item collections.
7. Move playable characters inside walkable areas.
8. See elements hide or disable based on conditions.

## Flows on top of scenes

When a scene element opens a flow, the scene dims and the flow appears on top. The player completes the dialogue or branch, then returns to the map with any variable changes applied.

This is the main bridge between spatial design and narrative logic: a place on the map can start a conversation, modify state, and reveal or disable other map elements.

## Testing interactions

Use exploration mode to review scene logic before sharing the map. Check that conditions evaluate as expected, instructions update the right variables, walkable zones limit movement, patrols follow their route, and flows return to the correct scene state.
