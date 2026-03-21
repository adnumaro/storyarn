# Epic: Scene Entities as Variables

> **Status:** Planning
> **Priority:** High — core differentiator of the platform
> **Last Updated:** 2026-03-20

---

## Vision

Pins and zones become first-class variable entities in the Storyarn system. Their properties can be read and modified at runtime from flow instruction/condition nodes, enabling dynamic scenes that react to narrative events.

Today, only sheet blocks are variables. After this epic, a designer can write instructions like:

- `guard.west.flow_id = flow.guard_post_battle` (change NPC dialogue after an event)
- `guard.west.hidden = true` (hide an NPC after they leave)
- `kael.is_leader = false`, `lyra.is_leader = true` (switch controlled character)
- `tavern.door.hidden = false` (reveal a zone after discovering it)

---

## Architecture Decisions

### AD-1: Pins and zones get shortcuts

Like sheets/flows/scenes, pins and zones get auto-generated shortcuts from their label/name. Unique constraint `(scene_id, shortcut)` for each.

- Pin: label "Guard West" -> shortcut `guard.west`
- Zone: name "Tavern Door" -> shortcut `tavern.door`
- Uses existing `NameNormalizer.shortcutify/1` pipeline

### AD-2: `sheet_id` is a template, not identity

A sheet linked to a pin is a visual/data template (avatar, stats). Multiple pins can share the same sheet (3 guards with the same "Guard" sheet, each with different label, flow, and shortcut).

No unique constraint on `(scene_id, sheet_id)`.

### AD-3: Dedicated `flow_id` field on pins

Pins get a new `flow_id` field (FK to flows) independent of `sheet_id`. This is the flow launched when clicking the pin in exploration mode. Replaces the overloaded `target_type/target_id` mechanism for flow launching.

### AD-4: Properties split into system vs variable

Each pin/zone property is either:

- **System** (cog icon in UI) — not modifiable at runtime. Examples: `layer_id`, `position_x`, `position_y`, `locked`, `pin_type`, `size`, `color`, `opacity`
- **Variable** (variable icon in UI) — readable and writable from flow instructions/conditions

**Pin variable properties:**

| Property      | Type      | Description                        |
|---------------|-----------|------------------------------------|
| `flow_id`     | reference | Flow launched on click             |
| `hidden`      | boolean   | Whether pin is visible (NEW field) |
| `is_playable` | boolean   | Player-controllable character      |
| `is_leader`   | boolean   | Currently controlled character     |
| `condition`   | map       | Visibility condition               |

**Zone variable properties:**

| Property      | Type      | Description                         |
|---------------|-----------|-------------------------------------|
| `target_type` | select    | Navigation target type (scene/flow) |
| `target_id`   | reference | Navigation target                   |
| `hidden`      | boolean   | Whether zone is visible (NEW field) |
| `action_type` | select    | Behavior type                       |
| `is_walkable` | boolean   | Traversable area                    |
| `condition`   | map       | Visibility condition                |

### AD-5: Variable reference format

Pin/zone variables are referenced as: `{pin_shortcut}.{property}` or `{zone_shortcut}.{property}`

Examples:
- `guard.west.flow_id`
- `guard.west.hidden`
- `tavern.door.is_walkable`

These integrate into the existing variable system alongside sheet variables (`mc.kael.health`). The condition builder and instruction builder need to support this new variable source.

### AD-6: Runtime state lives in exploration session

Variable modifications happen in the exploration player's runtime state (assigns), not persisted to DB. The DB holds the "initial state" (design-time defaults). Each exploration session starts fresh from DB state.

Future consideration: session persistence (save/load) is a separate feature.

---

## Phases

### Phase 1: Foundation — Shortcuts + Flow Field + Hidden

**Goal:** Pins and zones become identifiable entities with dedicated flow launching.

1. **Pin/zone shortcuts** — Add `shortcut` field to `scene_pins` and `scene_zones`. Auto-generate from label/name. Unique constraint `(scene_id, shortcut)`.
2. **Pin `flow_id`** — New FK field. Replaces `target_type="flow"` for pin flow launching.
3. **Pin `hidden` field** — New boolean, default false. Replaces condition_effect="hide" as a direct toggle.
4. **Zone `hidden` field** — Same for zones.
5. **Remove `target_type/target_id` from pins** — Flow launching now uses `flow_id`. Scene navigation for pins is not needed (pins are not navigation elements).
6. **UI updates** — Pin panel shows flow picker (dedicated), hidden toggle, system/variable icons on properties.
7. **Exploration player** — Use `flow_id` instead of `target_type/target_id` for pin clicks. Respect `hidden` field.
8. **Export/import** — Include new fields, maintain backwards compatibility.

### Phase 2: Variable Integration

**Goal:** Pin/zone properties addressable from flow instructions/conditions.

1. **Variable registry** — Extend `Sheets.list_project_variables/1` (or new function) to include pin/zone variables from all project scenes.
2. **Instruction builder** — Support assigning values to pin/zone properties.
3. **Condition builder** — Support reading pin/zone properties in conditions.
4. **Exploration runtime** — When a flow instruction modifies a pin/zone variable, update the exploration player state and re-render affected elements.

### Phase 3: Cross-Scene Flow Continuity (separate task)

**Goal:** A flow can trigger a scene change and continue executing in the new scene.

Example: NPC says "Let's talk inside" -> scene changes to interior -> flow continues with next dialogue node.

This is a complex feature involving:
- Flow node that triggers scene navigation mid-execution
- Preserving flow execution state across scene transitions
- Coordinating exploration player state transfer

> **See:** `docs/plans/pending/CROSS_SCENE_FLOW_CONTINUITY.md`

---

## Files Impact (Phase 1)

| Area          | Files                                          |
|---------------|------------------------------------------------|
| Schema        | `scene_pin.ex`, `scene_zone.ex`                |
| Migration     | New migration for shortcuts, flow_id, hidden   |
| Context       | `scenes/pin_crud.ex`, `scenes/zone_crud.ex`    |
| Serializer    | `scene_live/helpers/serializer.ex`             |
| UI - Panel    | `scene_element_panel.ex`                       |
| UI - Toolbar  | `floating_toolbar.ex`                          |
| Handlers      | `element_handlers.ex`, `show.ex`               |
| Exploration   | `exploration_player.js`, `exploration_live.ex` |
| Export/Import | `storyarn_json.ex` (both)                      |
| Versioning    | `scene_builder.ex`                             |
| Tests         | Pin/zone schema tests, exploration tests       |

---

## Open Questions

1. **Variable picker UX** — How does the instruction builder distinguish between sheet variables and pin/zone variables? Grouped sections? Different icon?
2. **Shortcut collisions** — Pin shortcut `guard.west` could theoretically collide with a sheet shortcut `guard.west`. Since they're in different namespaces (pin vs sheet) this is fine at DB level, but the variable picker UI needs to disambiguate. Prefix in picker? Category headers?
3. **Zone navigation** — Zones currently use `target_type/target_id` for scene navigation. This stays for zones (they ARE navigation elements). But should zones also get a `flow_id` for launching flows independently of navigation?
