# Scene & Interaction Model

## Problem Statement

Storyarn's flow editor and preview player currently treat narrative (flows) and space (maps) as independent systems. When playing a flow like the Morte first encounter from Planescape: Torment, the dialogue occurs "in the dark" — there's no visual context of WHERE the conversation takes place. The player has no spatial agency between dialogue beats.

For the stress test to succeed, a game designer must be able to recreate the core experience of a point & click RPG: explore a location, interact with objects and characters, trigger dialogues, modify game state through actions, and transition between scenes.

**The goal is NOT to build a game engine.** Storyarn is a narrative design tool. The preview player must be faithful enough for a designer to **validate the experience** — see how the story feels spatially, verify variable-driven branching, and test scene transitions.

## The Spectrum of Game Idioms

Different games relate to space differently:

| Type | Example | The world is... | Storyarn approach |
|------|---------|-----------------|-------------------|
| Visual novel | Doki Doki, Ren'Py games | A backdrop. Flow is everything. | Flows only. Scene nodes for context. |
| Point & click | Torment, Monkey Island | The protagonist. Exploration IS gameplay. | Maps as scenes. Zones/pins trigger flows. |
| RPG action | Witcher 3, Cyberpunk | A container. Narrative occurs within the world. | Flows with `scene_scene_id` for backdrop. |
| Sandbox | Dwarf Fortress | Emergent. No predefined narrative. | Out of scope. |

Storyarn must cover the first two well, and the third reasonably. The model must adapt without being excessively complex for any single case.

## Architecture: Three Pillars

```
Maps   = Space    (exploration, WHERE things happen)
Flows  = Behavior (dialogue, conditions, instructions — WHAT happens)
Sheets = State    (variables, the single source of truth)
```

**Zones and Pins** are the bridge between Maps and Flows.
**Sheets** are the bridge between everything.

## Current State (What Exists Today)

### Interaction Nodes (flow node type: `interaction`)

Currently functional. An interaction node references a map (`scene_id` in node data). When the preview player reaches this node:

1. The map renders as a full background image
2. Zones overlay the map as clickable polygons
3. Zone action types determine behavior:
   - **instruction**: Click executes variable assignments (stays in exploration)
   - **display**: Shows live variable value (read-only, updates reactively)
   - **event**: Click advances the flow through the zone's output connection
   - **navigate**: Inert in player (editor-only navigation)

**Files:** `lib/storyarn/flows/flow_node.ex`, `lib/storyarn_web/live/flow_live/player/slide.ex`, `lib/storyarn_web/live/flow_live/player/components/player_interaction.ex`, `assets/js/hooks/interaction_player.js`

### Scene Nodes (flow node type: `scene`)

Metadata-only. Establishes location/time context (INT/EXT, location name, time of day, description). Auto-advances in the player — shown as a brief transition card, not interactive.

Does NOT reference a map. Scene and interaction are currently unrelated concepts.

### Map Pins

Pins support `target_type` (sheet | flow | map | url) + `target_id`. **Pins CAN already reference flows** — the schema supports it. However, pins are NOT used in the player — only zones are interactive in preview.

**Fields of interest:** `target_type`, `target_id`, `pin_type` (location | character | event | custom), `label`, `tooltip`, `position_x`, `position_y`.

### Map Zones

Zones have `action_type` (navigate | instruction | display | event) with variable integration. Also have `target_type/target_id` for references.

**No conditions.** All zones render regardless of game state. A zone cannot be hidden or disabled based on variables.

### Preview Player Engine

Pure functional state machine (`Storyarn.Flows.Evaluator.Engine`). Tracks: current node, current flow, variables (from sheets), snapshots (undo), pending choices, console logs.

**Auto-advances** through non-interactive nodes: entry, hub, condition, instruction, jump, scene, subflow.
**Stops at** interactive nodes: dialogue, exit, interaction.

**Entry point is always a flow.** There is no way to start preview from a map.

### Sheets as Game State

Sheets are the single source of truth for game variables. Block fields on sheets become variables (unless `is_constant: true`). The engine reads/writes these during flow execution.

Variable reference format: `{sheet_shortcut}.{variable_name}` (e.g., `mc.morte.in_party`).

---

## Proposed Model

### Deprecation: Interaction Nodes

**Interaction nodes are removed.** Their function is fully absorbed by maps.

**Rationale:** If the map is the scene container, and pins/zones on the map trigger flows, then an "interaction node" inside a flow is redundant. The map already IS the interaction. Exploration is the default state — flows are interruptions of exploration, not the other way around.

**What replaces them:**
- Maps render as scenes via `scene_scene_id` on flows, or as standalone preview entry points
- Zone actions (instruction, display) work during exploration mode on the map
- Zone/pin `target_type: "flow"` triggers flows directly
- Zone/pin `target_type: "map"` performs scene transitions

**Migration path:** Existing interaction nodes will be converted. The `scene_id` from the node data becomes `scene_scene_id` on the parent flow. Zone configurations are preserved on the referenced map. Event-type zones that advanced the flow's internal connections will be migrated to reference their target flows directly via `target_type/target_id`.

### Preservation: Scene Nodes

Scene nodes remain for screenplay/narrative workflows. They serve a formatting purpose ("INT. MORTUARY - NIGHT") useful for visual novels, Fountain export, and narrative structure in projects that don't use maps.

| | Scene node | `scene_scene_id` |
|---|-----------|----------------|
| Purpose | Narrative formatting | Spatial context |
| Visual | Transition card (auto-advances) | Map backdrop (interactive) |
| Use case | Screenplays, visual novels | Point & click, RPGs |
| Required? | Optional | Optional |

A flow can use both, one, or neither. They are complementary.

### New: `scene_scene_id` on Flows

An optional field on the Flow schema referencing a Map entity.

- Provides visual backdrop for all nodes in the flow during preview
- Inherited by child flows (same pattern as sheet property inheritance)
- Override in child flow = scene transition
- `nil` = no spatial context (visual novel mode, current behavior)

**Resolution order** (first match wins):
1. Flow's own `scene_scene_id` (if explicitly set) — authoritative, IS a scene transition
2. Caller's `scene_scene_id` (if flow is invoked as subflow) — inherited from runtime context
3. Tree parent's `scene_scene_id` (if flow is organized under a parent) — inherited from hierarchy
4. `nil` — no spatial context

This means: a child flow with its own `scene_scene_id` always triggers a scene transition, regardless of what the caller has. A child flow without `scene_scene_id` inherits from whoever called it at runtime, not from its organizational parent.

**In the player:**
- **Play from a map** → exploration mode on that map (zones/pins interactive)
- **Play from a flow** → flow mode (the flow executes normally). If `scene_scene_id` resolves, the map renders as static backdrop behind dialogue slides. Does NOT enter exploration mode.
- Flow has no `scene_scene_id` → no backdrop (current behavior preserved)
- Exploration mode is ONLY entered from: (a) playing a map directly, or (b) a flow returning to the map after exit (exit node with no target during an exploration session)

### Exploration Mode

Exploration mode is the preview of a map with its interactive elements. It is NOT a flow engine state — it is the **map player**, a separate visualization layer.

**What it does:**
- Renders the map with its background image
- Shows zones and pins as interactive overlays
- Evaluates conditions on zones/pins (from current sheet state) to determine visibility
- Handles clicks: executes zone instructions, launches flows from pin/zone targets
- Re-evaluates conditions after any state change (instruction execution, flow return)

**What it does NOT do:**
- Run a flow engine. Between flow triggers, no flow is executing.

**Variable state management:**

Exploration mode maintains a **local variable state** initialized from sheets on session start. This is the same pattern the flow engine uses.

- Exploration instruction executions update the local state
- When a flow is triggered, the flow engine receives the current local state
- When the flow terminates, its final state becomes exploration's local state
- Condition evaluations always read from this local state (not from DB)
- State is ephemeral — closing the preview discards all changes (sheets in DB are unchanged)

**Entry points:**
- **From a map:** Click "Play" on a map → exploration mode on that map directly. Pins/zones with flow targets are interactive.
- **From a flow:** Click "Play" on a flow → flow mode (the flow executes). If `scene_scene_id` resolves, the map renders as static backdrop. Exploration mode is NOT entered — the flow runs normally.

### The Game Loop

```
┌─────────────────────────────────────────────────────────┐
│                   EXPLORATION MODE                       │
│  Map player renders the map.                            │
│  Zones/pins evaluated against sheet variables.          │
│                                                          │
│  Player clicks pin (target: flow) ───────────────────┐  │
│  Player clicks zone (instruction) → executes, stays  │  │
│  Player clicks zone (target: map) → scene transition │  │
└──────────────────────────────────────────────────────│──┘
                                                       │
                                                       ▼
┌─────────────────────────────────────────────────────────┐
│                    FLOW MODE                             │
│  Flow engine executes the triggered flow.               │
│  Map stays as backdrop behind dialogue UI.              │
│  Sheet variables are read/written by the flow.          │
│                                                          │
│  Flow reaches exit node ─────────────────────────────┐  │
└──────────────────────────────────────────────────────│──┘
                                                       │
                              ┌─────────────────────────┤
                              │                         │
                    Exit has target?              No target
                              │                         │
                              ▼                         ▼
                   Target determines          Return to exploration
                   next action:               on the SAME map.
                   - map → transition         Conditions re-evaluated.
                   - flow → chain to flow
```

### Zone Action Model (Revised)

**Separation of concerns:** Zone behavior (what it does locally) and zone trigger (what it launches) are independent.

| Field | Controls | Values |
|-------|----------|--------|
| `action_type` | Local behavior on click | `instruction`, `display`, `none` (default) |
| `target_type` + `target_id` | What to launch on click | `flow`, `map`, `sheet`, `url` (already exists in schema) |

These combine freely:

| Combination | Behavior |
|------------|----------|
| `instruction` only | Execute variable assignments, stay in exploration |
| `display` only | Show live variable value (read-only, no click action) |
| `target: flow` only | Click launches the referenced flow |
| `target: map` only | Click transitions to another map |
| `instruction` + `target: flow` | Execute instruction FIRST, then launch flow (deterministic order) |
| `display` + `target: flow` | Show variable value; click launches flow |
| `none` + no target | Visual-only zone (not clickable) |

**Deprecated action types:**
- `event` → replaced by `target_type: "flow"`. Migration: map the event zone's flow connection to a direct flow reference.
- `navigate` → replaced by `target_type: "map"`. Migration: already uses `target_type/target_id` in most cases.

### Exit Node Targeting

Exit nodes gain `target_type` / `target_id` capability (consistent with pins and zones):

| Exit node config | Behavior |
|-----------------|----------|
| No target (default) | Return to exploration mode on the current map |
| `target_type: "map"` | Scene transition — exploration resumes on the target map |
| `target_type: "flow"` | Chain to another flow (similar to jump/subflow) |

This gives the designer explicit control over what happens when a flow ends, without adding new concepts. The `target_type/target_id` pattern is already used by pins and zones — exit nodes simply gain the same capability.

### Conditions on Zones and Pins

**Add a `condition` field to both MapZone and MapPin schemas.**

Uses the same condition structure as flow condition nodes:

```json
{
  "logic": "all",
  "rules": [
    { "sheet": "inventory", "variable": "has_scalpel", "operator": "equals", "value": "false" }
  ]
}
```

When condition evaluates to false:
- **Hidden** (`condition_effect: "hide"`) — not rendered at all
- **Disabled** (`condition_effect: "disable"`) — rendered but not clickable, visually dimmed

This reuses the existing condition evaluation engine — no new logic needed.

### Pin Interactivity in Player

Pins with `target_type: "flow"` become clickable in exploration mode. Click launches the referenced flow. Pins follow the same condition evaluation as zones.

**Pins gain `action_type` + `action_data`** (same fields as zones). This enables simple interactions without requiring a flow:
- Pin "Key" (`action_type: "instruction"`, `action_data: {assignments: [{ref: "inventory.has_key", value: "true"}]}`) — click picks up the key, no flow needed.
- Pin "Morte" (`target_type: "flow"`, `target_id: dmorte1_flow_id`) — click launches dialogue flow.
- Pin "Chest" (`action_type: "instruction"` + `target_type: "flow"`) — execute instruction first, then launch flow.

This is the primary mechanism for NPC interactions:
- Pin "Morte" (`pin_type: "character"`, `target_type: "flow"`, condition: `morte.met == false`)
- Click → launches DMORTE1 flow
- Flow ends → back to map, conditions re-evaluated

---

## Applied Example: Planescape: Torment — Mortuary Escape

### Map: Mortuary 2nd Floor

Interactive elements:

| Element | Type | action_type | target_type | Condition |
|---------|------|-------------|-------------|-----------|
| Morte | Pin (character) | — | flow: "DMORTE1" | `morte.met == false` · hide | Hidden once met |
| Morte (in party) | Pin (character) | — | flow: "DMORTE1 Hints" | `morte.in_party == true` · hide | Hidden until in party. Gap: when met but not yet in party (during dialogue), neither pin shows — intentional. |
| Shelves | Zone | instruction: `has_scalpel = true` | — | `has_scalpel == false` · hide | Disappears after pickup |
| Zombie ZM782 | Pin (character) | — | flow: "Zombie Combat" | `zm782_dead == false` · hide | Hidden after killed |
| Key (dropped) | Pin (event) | instruction: `has_key = true` | — | `zm782_dead == true AND has_key == false` · hide | Appears only after zombie killed, disappears after pickup |
| Door | Zone | — | map: "Mortuary 1F" | `has_key == true` · disable | Always visible. Dimmed until key obtained, then clickable for scene transition. |
| Scalpel count | Zone (display) | display: `inventory.has_scalpel` | — | — | Always visible |

### Flow tree

```
Mortuary Escape (scene_scene_id: Mortuary 2F)
├── DMORTE1 - First Meeting
│   ├── 18 dialogue states
│   ├── Condition: alignment check
│   └── Instruction: set morte.in_party = true
├── DMORTE1 - Walkthrough Hints
│   ├── 8 context-sensitive states
│   └── Branching: convince Morte to help fight
├── DMORTE1 - Rejoin
│   └── 4 states if TNO dismissed Morte
├── Zombie Combat
│   ├── Condition: combat outcome
│   └── Instruction: set zm782_dead = true
└── Mortuary 1F Exploration (scene_scene_id: Mortuary 1F ← override = transition)
    └── (next scene)
```

### Preview play sequence

1. Designer clicks "Play" on Mortuary 2F map (or on the Mortuary Escape flow)
2. **Exploration mode**: Mortuary 2F renders. Morte pin glows (condition `morte.met == false` is true → pin visible). Shelves zone visible (condition `has_scalpel == false` is true). Door zone dimmed (condition `has_key == true` is false → disabled).
3. Designer clicks Morte pin → **Flow mode**: DMORTE1 First Meeting plays. Map stays as backdrop behind dialogue.
4. Flow sets `morte.in_party = true` → Exit node (no target) → **Exploration mode** resumes.
5. Map re-evaluates: Morte pin changes to "in party" variant. Shelves zone still active.
6. Designer clicks Shelves → Zone `instruction` executes: `has_scalpel = true`. Stays in exploration. Zone disappears (condition no longer met).
7. Zombie pin is clickable. Designer clicks → **Flow mode**: Zombie Combat plays.
8. Flow sets `zm782_dead = true` → Exit (no target) → **Exploration mode**.
9. Key pin appears (conditions met). Designer clicks → instruction executes: `has_key = true`. Pin disappears.
10. Door zone activates. Designer clicks → `target_type: "map"` → **Scene transition** to Mortuary 1F.

---

## Gap Analysis

### What exists and works today

| Feature | Status | Notes |
|---------|--------|-------|
| Zone rendering + click handling | Working | `interaction_player.js` — reusable for exploration mode |
| Zone instruction/display actions | Working | Variable read/write from zones |
| Scene nodes | Working | Auto-advance with metadata card |
| Pin `target_type: "flow"` | Schema ready | Field exists, NOT used in player |
| Variable tracking for zones | Working | Read/write references tracked in `variable_references` table |
| Player engine (state machine) | Working | Handles flow execution, variables, undo |
| Flow hierarchy (parent/child) | Working | Subflow nodes reference child flows |
| Condition evaluation engine | Working | Used by condition nodes in flows — reusable for zone/pin conditions |

### What needs to be built

| Feature | Priority | Scope |
|---------|----------|-------|
| **`scene_scene_id` on Flow schema** | High | DB migration, schema change, inheritance logic |
| **Zone/pin conditions** | High | `condition` + `condition_effect` fields on MapZone/MapPin, evaluation in player |
| **Pin interactivity in player** | High | Render pins in exploration, handle clicks, trigger flows |
| **Map backdrop during flow mode** | High | Render map behind dialogue slides when `scene_scene_id` is set |
| **Exploration mode player** | High | Map player that renders map, evaluates conditions, handles zone/pin clicks. Reuses `interaction_player.js` rendering logic. |
| **Return-to-exploration after flow** | High | When triggered flow ends (exit with no target), resume exploration on same map |
| **Zone action_type cleanup** | High | Remove `event`/`navigate` action types, migrate to `target_type/target_id` |
| **Pin `action_type` + `action_data`** | High | Add to MapPin schema (same fields as zones) for simple interactions without flows |
| **Exit node targeting** | Medium | Add `target_type/target_id` to exit nodes |
| **Map-as-preview-entry-point** | Medium | "Play" button on maps, new route for map preview |
| **Flow `scene_scene_id` inheritance** | Medium | Child flows inherit parent's scene, caller context overrides |
| **Create flow from map pin** | Medium | UX: place pin → create linked flow directly from map editor |
| **Remove interaction node type** | Medium | Remove from node registry, UI, engine. Migrate existing data. |
| **Scene transition animations** | Low | Visual transition when map changes |

---

## Comparison with articy:draft

| Aspect | articy:draft | Storyarn |
|--------|-------------|----------|
| Scene definition | Fragment with "scene" flag | Map entity (visual, spatial) |
| What's inside a scene | Nested fragments | Zones/pins linking to flows |
| Exploration | Abstract (boxes and arrows) | Visual map with interactive elements |
| Dialogue trigger | Fragment connection | Zone/pin click |
| Variable conditions | On fragments | On zones/pins + flow conditions |
| Scene transition | Fragment → fragment | `scene_scene_id` override or zone/pin `target: map` |
| State management | Global variables | Sheets (hierarchical, inherited) |
| Exit behavior | Fragment terminates | Exit node targets (map, flow, or return to exploration) |

**Storyarn's advantage:** The designer can SEE where interactions are placed spatially. In articy, scene layout is abstract. In Storyarn, you see the Mortuary floor plan with Morte floating near the slab, the shelves on the wall, and the zombie by the door. The map is not a diagram — it's the actual scene.

---

## Open Questions

1. **Combat abstraction:** Torment has combat. Recommendation: abstract as a condition node ("combat outcome: win/lose") with designer-chosen results. Storyarn validates narrative flow, not game balance. Is this sufficient?

2. **Multiple simultaneous scenes:** Can the player show multiple maps at once (split-screen)? Current recommendation: no. One scene at a time. Revisit if needed.

3. **Creating flows from pins in map editor:** The designer should be able to place a pin, set `target_type: "flow"`, and create a new flow directly from the map editor UI. The flow is auto-linked to the pin. This streamlines the workflow for spatial game design.

---

*Document created: 2026-02-23*
*Last updated: 2026-02-23*
*Context: Stress test with Planescape: Torment data*
*Related: `docs/stress_test/issues.md`, `IMPLEMENTATION_PLAN.md`*
