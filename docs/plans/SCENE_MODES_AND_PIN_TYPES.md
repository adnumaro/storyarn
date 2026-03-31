# Scene Redesign: Toolset Filters, Pin Types & Zone Capabilities

## Problem Statement

Scene V2 has powerful features (exploration, patrols, player control) but they're hard to discover and confusing to configure:

1. **Too many tools at once.** A designer making a simple map sees the same tools as someone prototyping a full RPG. No progressive disclosure — everything is visible, nothing is explained by context.
2. **Setting up a player is unintuitive.** You create a regular pin, optionally attach a sheet, then toggle `is_playable` + `is_leader` buried in pin settings. Exploration mode doesn't work without a player, but nothing guides you toward creating one.
3. **NPC patrols feel wrong.** Patrol config lives on the NPC pin itself. Patrol stops are regular pins with `hidden: true`. There's no concept of "wait here for 3 seconds before moving on." The animation is continuous with no natural pauses.
4. **Connections serve two unrelated purposes.** Visual map connections (trade routes, borders) and patrol routes use the same tool with the same UI. Patrol routes don't need arrows, labels, or style options.
5. **Zones are overloaded.** A single `action_type` switch + `action_data` JSON blob handles walkable areas, instructions, display, collections, and navigation. Each action_type has its own unvalidated data structure embedded in a map field. Collections store full entity data (id, sheet_id, label, condition, instruction) inside JSON — effectively entities without schemas.

---

## Solution Overview

### 1. Toolset Filter System (replaces scene_mode)

Instead of a `scene_mode` field in the database that locks a scene into one type, the editor dock has a **toolset filter** — a UI-only toggle that controls which tools are visible. No schema change. No backend logic. Pure frontend.

**Filter groups (mutually exclusive — select one at a time):**

| Group         | Purpose                                          | Tools shown                                                                                                                                                 |
| ------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Essential** | First contact. Minimum viable scene editing.     | Layers, pins (location, character), basic zones (no actions), background asset config                                                                       |
| **Map**       | Interactive maps, infographics, flow backgrounds | Pins (all standard types), connections (visual with full style options), zone condition, zone navigation, zone flow, zone display, zone instruction (click) |
| **Prototype** | Game prototyping (RPG, CRPG, point & click)      | Player pin, waypoint pin, walkable zones, patrol config, companion config, collection zones, connections (patrol routes), on_enter instruction              |
| **All**       | Everything visible                               | All tools from all groups                                                                                                                                   |

**Key rules:**

- Groups are **exclusive**, not inclusive. Each group shows only its own tools. "All" shows everything.
- The filter is stored as a **user preference** (localStorage), not in the scene schema. The backend has no opinion — any combination of elements is valid.
- **Annotations** are NOT part of any tool group. They live in the actions bar (alongside version history, play button, etc.) and are always visible. Annotations are communication tools, not design tools.
- The filter affects: dock tools, pin creation menu, zone property panels (which fields/sections are shown), connection tool behavior.

**Why this is better than scene_mode in DB:**

- No schema migration, no backend validation per mode.
- A scene can freely use tools from any group — the designer is never locked out.
- Scales naturally: adding a future group (e.g., "Cinematic") is a frontend-only change.
- Progressive disclosure without limitation.

### 2. Player Pin (New pin_type)

A dedicated `pin_type: "player"` replaces the confusing `is_playable` + `is_leader` flags.

**Characteristics:**

- Required for exploration play. If no player pin exists, the "Play" button shows a tooltip: "Add a player pin to enable exploration mode."
- Maximum 1 per scene.
- Sheet is optional but recommended. Without a sheet, renders as a generic icon (Lucide `user`). With a sheet, uses the sheet avatar. Editor shows a visual hint (warning border or tooltip) when no sheet is assigned.
- Does NOT have: `flow_id`, `condition`, `condition_effect`. The player is always visible.
- Visual distinction: small crown icon overlay on the pin (does not replace the sheet avatar).
- The player pin's position IS the default spawn point for the scene.

**Removed fields (delete, not deprecate — no users):**

- `is_playable` — replaced by `pin_type: "player"`
- `is_leader` — implicit in `pin_type: "player"`

**Updated pin_type enum:**

```
location | character | event | custom | player | waypoint
```

**Toolset group:** Prototype

### 3. Companion System (Visual Only — V1)

Character pins with sheets can be marked as companions.

**New field on pin:**

```elixir
field :is_companion, :boolean, default: false
```

**V1 behavior (visual only):**

- Companions follow the player with automatic fixed offset (formation behind leader).
- Companions appear in a party bar in the exploration toolbar (avatars only).
- Companions do NOT interact with pins, zones, or flows independently.
- Companions do NOT have individual selection or movement.

**Future (not implemented now):**

- Click companion avatar to select individually (CRPG-style party management).
- Selected companion moves independently, can interact with the world.
- Unselected companions stay where they are.
- "Select all" returns to group movement.
- When a companion interacts, need to resolve: whose variable context applies?

**Toolset group:** Prototype

### 4. Waypoint Pin (New pin_type)

A dedicated `pin_type: "waypoint"` replaces the pattern of "hidden regular pins as patrol stops."

**Visual:**

- Editor: flag/pennant icon (Lucide `flag-triangle-right`). Clearly distinct from regular pins.
- Exploration play: invisible. Waypoints never render in play mode, only in the editor.

**Fields:**

- `pause_ms` (integer, default 0) — how long the NPC waits at this point before continuing to the next waypoint. 0 = no pause.
- `speed_override` (float, nullable) — movement speed toward the NEXT waypoint. null = use the NPC's base patrol speed.

**Does NOT have:** sheet, flow, condition, condition_effect, tooltip, label, icon, size. A waypoint is a route point, not an interactive entity.

**How patrols work with waypoints:**

1. The NPC (character pin) defines `patrol_mode` (`none | loop | ping_pong | one_way`) — the global route behavior.
2. Connect the NPC to waypoint(s) via scene connections (patrol route type).
3. The NPC moves to the first connected waypoint. At arrival, waits `pause_ms`, then moves to the next at `speed_override` (or base speed if null).
4. After the last waypoint, behavior depends on `patrol_mode`: loop back to first, reverse direction, or stop.
5. No collision system — the designer manually draws patrol routes around obstacles using connection waypoints (double-click to add curve points). The NPC follows the drawn path exactly.

**Removed from NPC pin (character pin):**

- `patrol_pause_ms` — replaced by per-waypoint `pause_ms`

**Kept on NPC pin:**

- `patrol_mode` — defines route behavior (loop/ping_pong/one_way)
- `patrol_speed` — base speed, used when waypoint has no `speed_override`

**Toolset group:** Prototype

### 5. Connections — Two Distinct Behaviors

Connections (`SceneConnection`) serve fundamentally different purposes. The schema stays the same, but availability, rendering, and allowed pin combinations differ by context.

**Visual connections (Map group):**

- Full-featured: line style (solid/dashed/dotted), color, label, bidirectional toggle, arrows, waypoints (curve points).
- Purpose: trade routes, borders, relationships between locations. Informative and decorative.
- Rendered in both editor and play.
- Available between any standard pin types (location, character, event, custom).

**Patrol routes (Prototype group):**

- Connections ONLY between character pins and waypoints, or between waypoints.
- Purpose: define NPC patrol paths. The connection's intermediate waypoints (curve points in the `waypoints` array) define the actual movement path around obstacles.
- Rendering in editor: subtle thin dotted line, no arrows, no labels. Just a guide for the designer.
- Rendering in play: invisible.
- Fields used: `waypoints` (intermediate curve points). Fields ignored: `label`, `show_label`, `line_style`, `line_width`, `color`, `bidirectional`.

**Editor enforcement:**

- When filter is Map or Essential: connection tool works between standard pins. Full style options in connection panel.
- When filter is Prototype: connection tool only allows character↔waypoint and waypoint↔waypoint. Style options hidden.
- When filter is All: both behaviors available, determined by which pins are being connected.

### 6. Zone Capabilities Redesign

**Current problem:** Zones use `action_type` (enum switch) + `action_data` (untyped JSON blob). This forces one action per zone, stores full entity data in JSON without validation, and conflates spatial properties with interaction logic.

**New approach:** Remove `action_type` and `action_data`. Replace with independent, typed, optional capabilities that can be combined.

#### Zone capabilities

| Capability                 | Fields                                       | Toolset group | Trigger  | Description                                                                                             |
| -------------------------- | -------------------------------------------- | ------------- | -------- | ------------------------------------------------------------------------------------------------------- |
| **Walkable**               | `is_walkable: boolean`                       | Prototype     | Spatial  | Player can walk through this zone                                                                       |
| **Condition**              | `condition: map`, `condition_effect: string` | Map           | Auto     | Controls zone visibility/accessibility based on variables                                               |
| **Navigation**             | `target_type: string`, `target_id: integer`  | Map           | Click    | Click to navigate to another scene                                                                      |
| **Flow**                   | `flow_id: integer` (FK, new)                 | Map           | Click    | Click to execute a flow (dialogue, narrative sequence)                                                  |
| **Display**                | `display_variable_ref: string` (new)         | Map           | Reactive | Renders the live value of a variable on the canvas (e.g., stat counters in a character creation screen) |
| **Instruction (click)**    | `click_assignments: map` (renamed)           | Map           | Click    | Execute variable assignments on click (e.g., +/- buttons for stats)                                     |
| **Instruction (on_enter)** | `on_enter_assignments: map` (new)            | Prototype     | Auto     | Execute variable assignments when player walks into the zone                                            |
| **Collection**             | `collection_sheet_ids: [integer]` (new)      | Prototype     | Click    | Sheets available for pickup in this zone (cofre/baúl/armario)                                           |

#### Removed fields

- `action_type` — no more switch, each capability is independent
- `action_data` — each capability has its own typed field

#### How capabilities combine

**Enchanted chest (baúl hechizado):**

- `flow_id` → flow with dialogue, choices, consequences
- `collection_sheet_ids` → [sword_id, potion_id, ring_id]
- `condition` → requires "has_key" variable = true
- Flow executes first. Its variable changes can affect which sheets are available for collection.

**Simple loot chest:**

- `collection_sheet_ids` → [coin_id, dagger_id]
- No flow, no condition. Click → modal with items.

**Door to another scene:**

- `target_type: "scene"`, `target_id: 42`
- `condition` → requires "has_dungeon_key" = true

**Trap zone:**

- `on_enter_assignments` → subtract 10 HP on entry
- `is_walkable: true`

**Character creation screen (Planescape: Torment style):**

- Display zones showing STR, DEX, INT values (`display_variable_ref`)
- Instruction zones as +/- buttons (`click_assignments`)
- All on a decorative background asset
- No player, no movement — pure Map group tooling

**Guard at a door (complex combination):**

- `flow_id` → dialogue with the guard
- `target_type: "scene"` → navigate if flow ends well
- `condition` → only visible if guard not defeated
- `collection_sheet_ids` → guard drops his sword

#### Execution order on click interaction

1. **Condition** — can the player access this zone? If not, stop.
2. **Flow** — if `flow_id` exists, execute first. Result may modify variables.
3. **Instruction (click)** — if `click_assignments` exists, execute.
4. **Collection** — if `collection_sheet_ids` exists, show loot modal (filtered by variables post-flow).
5. **Navigation** — if `target_type` exists, navigate to target scene.

`on_enter_assignments` is separate — triggers when the player walks into the zone, not on click.

#### Collection details

- **Items are sheets.** No embedded JSON entities. The zone stores `collection_sheet_ids` — a list of sheet IDs. Name and avatar come from the sheet itself.
- **Tracking is per-zone.** Collecting "Gold Coin" from Chest A does not affect Chest B. Session stores `collected_ids` as `["{zone_id}:{sheet_id}", ...]`.
- **Modal display:** Shows sheet avatar + name for each available item. Items already collected in this zone are filtered out.
- **Flow interaction:** If the zone has both `flow_id` and `collection_sheet_ids`, the flow runs first. The flow can modify variables, which can affect conditions on the zone or items. After the flow completes, the collection modal opens.

### 7. Spawn Points

**Current problem:** When navigating from scene A to scene B, where does the player appear?

**V1 solution (simple):**

- The player pin position IS the spawn point. Entering a scene = appear at player pin position.

**Future solution (not implemented now):**

- `pin_type: "spawn"` — defines named entry points in a scene.
- Child scene defines N spawn points (named entry positions).
- Parent scene's navigation zone selects which spawn point to use (list populated from child scene's spawns).
- Conditions on spawn selection: "if variable X, spawn at entrance A; otherwise spawn at entrance B."

---

## Schema Changes Summary

### Scene

No schema changes. Toolset filter is UI-only (localStorage).

### ScenePin

| Field             | Change                                                                               |
| ----------------- | ------------------------------------------------------------------------------------ |
| `pin_type`        | **MODIFIED** — add `"player"`, `"waypoint"` to enum                                  |
| `is_playable`     | **REMOVED**                                                                          |
| `is_leader`       | **REMOVED**                                                                          |
| `is_companion`    | **NEW** — `boolean`, default `false`. Only meaningful on character pins with sheets. |
| `patrol_pause_ms` | **REMOVED** — lives on waypoint's `pause_ms`                                         |
| `pause_ms`        | **NEW** — `integer`, default `0`. Only for waypoint pins.                            |
| `speed_override`  | **NEW** — `float`, nullable. Only for waypoint pins.                                 |

**Kept as-is:**

- `patrol_mode` on character pins (route behavior)
- `patrol_speed` on character pins (base speed, used as default when waypoint has no override)

### SceneZone

| Field                  | Change                                                                                                            |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `action_type`          | **REMOVED**                                                                                                       |
| `action_data`          | **REMOVED**                                                                                                       |
| `flow_id`              | **NEW** — `integer`, FK to Flow, nullable                                                                         |
| `display_variable_ref` | **NEW** — `string`, nullable. Variable reference to display live value.                                           |
| `click_assignments`    | **NEW** — `map`, nullable. Variable assignments executed on click. (Replaces `action_data` for instruction type.) |
| `on_enter_assignments` | **NEW** — `map`, nullable. Variable assignments executed on zone entry.                                           |
| `collection_sheet_ids` | **NEW** — `{:array, :integer}`, default `[]`. Sheet IDs available for collection.                                 |

**Kept as-is:**

- `is_walkable`, `condition`, `condition_effect`, `target_type`, `target_id`
- All visual fields (vertices, colors, borders, opacity)

### SceneConnection

No schema changes. Rendering behavior determined by connected pin types.

### ExplorationSession

| Field           | Change                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------- |
| `collected_ids` | **MODIFIED** — format changes from `["uuid"]` to `["{zone_id}:{sheet_id}"]` for per-zone tracking |

---

## Toolset Filter — Tool Assignment

### Essential

- Layers (create, reorder, visibility, lock)
- Pins: location, character
- Zones: basic (visual only — vertices, fill, border, opacity, name)
- Background asset configuration
- Scene settings (dimensions, zoom, center)

### Map

- Pins: location, character, event, custom
- Connections: visual (full style options — line style, color, arrows, labels, bidirectional)
- Zone capabilities: condition, navigation, flow, display, instruction (click)

### Prototype

- Player pin (max 1 per scene, crown overlay)
- Waypoint pin (flag icon, patrol route points)
- Connections: patrol routes (character↔waypoint, subtle dotted rendering)
- Zone capabilities: walkable, on_enter instruction, collection
- Pin config: patrol_mode, patrol_speed (on character pins)
- Pin config: is_companion (on character pins with sheets)

### Always visible (not filtered)

- Annotations (in actions bar, not dock)
- Version history
- Play button (exploration mode — shows warning if no player pin)
- Ambient flows
- Undo/redo

---

## Validation Warnings in Editor

These warnings are always active regardless of the selected toolset filter.

| Condition                                                         | Warning                                                    |
| ----------------------------------------------------------------- | ---------------------------------------------------------- |
| Scene has player pin but no exploration button visible            | — (button is always visible)                               |
| No player pin exists + user clicks Play                           | Tooltip: "Add a player pin to enable exploration mode"     |
| Player pin without sheet                                          | Subtle hint on pin: "Assign a sheet for avatar display"    |
| NPC with patrol_mode != none but no connected waypoints           | Warning on pin: "Connect waypoints to define patrol route" |
| Zone with target_type: scene pointing to scene without player pin | Warning on zone: "Target scene has no player pin"          |

---

## Implementation Phases

### Phase A: Schema Changes

1. Add `player` and `waypoint` to pin_type enum
2. Remove `is_playable`, `is_leader` from ScenePin
3. Add `is_companion`, `pause_ms`, `speed_override` to ScenePin
4. Remove `patrol_pause_ms` from ScenePin
5. Zone: remove `action_type`, `action_data`
6. Zone: add `flow_id`, `display_variable_ref`, `click_assignments`, `on_enter_assignments`, `collection_sheet_ids`
7. Update all changesets and validations
8. Update PropsSerializer for new fields
9. Update ExplorationSession `collected_ids` format

### Phase B: Toolset Filter System

1. Implement filter toggle in dock UI (Essential / Map / Prototype / All)
2. Tag each tool/panel section with its group
3. Dock renders only tools matching active filter
4. Pin creation menu adapts to active filter
5. Zone property panels show/hide capability sections per filter
6. Connection tool adapts behavior per filter (visual vs patrol route)
7. Store filter preference in localStorage

### Phase C: Pin Types — Player & Waypoint

1. Player pin creation with crown overlay icon
2. Player pin validation (max 1 per scene, no flow/condition)
3. Waypoint pin creation with flag icon
4. Waypoint pin properties panel (pause_ms, speed_override)
5. Companion toggle on character pins
6. Play button warning when no player pin

### Phase D: Zone Capabilities

1. Zone property panel: render capability sections independently (condition, navigation, flow, display, instruction, collection, walkable)
2. Flow picker (select from project flows) in zone panel
3. Display variable ref picker in zone panel
4. Click assignments editor (reuse existing instruction builder)
5. On_enter assignments editor
6. Collection sheet picker (multi-select from project sheets)
7. Collection modal in exploration: read from `collection_sheet_ids`, show sheet avatar + name

### Phase E: Exploration Mode Updates

1. Update ExplorationLive to find player by `pin_type: "player"`
2. Companion follow system (visual only, fixed offset)
3. Party bar in toolbar (avatars, no selection)
4. Waypoint-based patrol: read `pause_ms` and `speed_override` from connected waypoints
5. Update `usePatrols.js` for new waypoint data structure
6. Collection tracking with `"{zone_id}:{sheet_id}"` format
7. Zone interaction: execute capabilities in order (condition → flow → instruction → collection → navigation)

### Phase F: Connection Behavior

1. Connection tool: detect connected pin types → apply visual or patrol route rendering
2. Patrol route rendering: thin dotted line, no arrows, no labels
3. Hide style options when connecting to/from waypoints
4. Visual connections: full style options (existing behavior)
