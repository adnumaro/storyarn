# Scene & Interaction Model — Implementation Plan

**Concept document:** `docs/concepts/SCENE_INTERACTION_MODEL.md`
**Estimated phases:** 7 (incrementally deliverable)

---

## Phase 1: Schema Foundations

**Goal:** All DB schema changes, no UI or player changes. Everything compiles and tests pass.

### 1.1 Add `scene_scene_id` to Flow schema

- **Migration:** Add `scene_scene_id` (references `maps`, nullable, on_delete: nilify_all)
- **Schema:** Add `belongs_to :scene_map, Storyarn.Maps.Map` to `flow.ex`
- **Changesets:** Add `scene_scene_id` to both `create_changeset/2` and `update_changeset/2`. The field is nullable — flows can be created with or without a scene map.
- **Foreign key constraint:** Add `foreign_key_constraint(:scene_scene_id)` to changesets
- **Context facade:** Add `update_flow_scene/2` to `Storyarn.Flows`

**Files:**
- `priv/repo/migrations/TIMESTAMP_add_scene_scene_id_to_flows.exs`
- `lib/storyarn/flows/flow.ex`
- `lib/storyarn/flows/flow_crud.ex`
- `lib/storyarn/flows.ex`

### 1.2 Add `condition` + `condition_effect` to MapZone

- **Migration:** Add `condition` (map, nullable), `condition_effect` (string, default: "hide")
- **Schema:** Add fields to `map_zone.ex`
- **Changesets:** Validate `condition_effect` in `["hide", "disable"]`
- **No action_data changes yet** — that's Phase 2

**Files:**
- `priv/repo/migrations/TIMESTAMP_add_conditions_to_map_zones.exs`
- `lib/storyarn/maps/map_zone.ex`

### 1.3 Add `condition` + `condition_effect` to MapPin

- **Migration:** Add `condition` (map, nullable), `condition_effect` (string, default: "hide")
- **Schema:** Add fields to `map_pin.ex`
- **Changesets:** Validate `condition_effect` in `["hide", "disable"]`

**Files:**
- Same migration as 1.2 (or separate)
- `lib/storyarn/maps/map_pin.ex`

### 1.4 Add `action_type` + `action_data` to MapPin

- **Migration:** Add `action_type` (string, default: "none"), `action_data` (map, default: `{}`)
- **Schema:** Add fields to `map_pin.ex`
- **Changesets:** Validate `action_type` in `["none", "instruction", "display"]`. Validate `action_data` per type (reuse same logic as zone validation).
- **Note:** Pins don't need `event` or `navigate` — those are handled by `target_type/target_id` which already exist.

**Files:**
- Same migration as 1.3 (or separate)
- `lib/storyarn/maps/map_pin.ex`

### 1.5 Variable reference tracking for pins

- **Extend** `VariableReferenceTracker` to track pin action_data (instruction: writes, display: reads)
- **Add** `source_type: "map_pin"` support — this requires new functions analogous to the existing `map_zone` variants:
  - `update_map_pin_references/1` — extract refs from pin action_data (mirrors `update_map_zone_references/1`)
  - `delete_map_pin_references/1` — cleanup on pin delete
  - `get_map_pin_variable_usage/2` — query pin refs for the sheet editor's variable usage section
  - `check_stale_map_pin_references/2` — stale detection for pins
  - Update `get_variable_usage/2` and `check_stale_references/2` to include pin results alongside flow node and zone results
- **Wire** into `PinCrud.create_pin/2` and `PinCrud.update_pin/2`

**Files:**
- `lib/storyarn/flows/variable_reference_tracker.ex`
- `lib/storyarn/maps/pin_crud.ex`

### Verification
```bash
mix ecto.migrate
mix compile --warnings-as-errors
mix test
```

---

## Phase 2: Zone Action Model Cleanup

**Goal:** Decouple `action_type` (local behavior) from `target_type` (trigger). Deprecate `event`/`navigate`. Migrate existing data.

**Critical prerequisite:** Three layers currently couple action_type to target_type and must all change in lockstep:
- **Changeset** (`map_zone.ex:147-153`): `maybe_clear_target/1` wipes `target_type`/`target_id` when action_type changes away from `"navigate"`
- **UI** (`floating_toolbar.ex`): Target picker conditionally rendered only when `action_type == "navigate"`
- **Player JS** (`interaction_player.js`): Ignores `target_type` entirely, only acts on `action_type`

### 2.1 Decouple changeset: remove `maybe_clear_target`

- **Remove** or rewrite `maybe_clear_target/1` — action_type changes must NOT wipe target fields
- **Change** schema default from `default: "navigate"` to `default: "none"` — "navigate" is being removed as a valid type
- **Update** `@valid_action_types` from `~w(navigate instruction display event)` to `~w(none instruction display)`
- **Keep reading old values** — the changeset only validates on write. Existing `event`/`navigate` zones still load from DB.

**Files:**
- `lib/storyarn/maps/map_zone.ex` — remove `maybe_clear_target/1`, update `@valid_action_types`, change default

### 2.2 Decouple UI: show target picker independently

- **Remove** the `:if={(@zone.action_type || "navigate") == "navigate"}` condition on the target picker section in `floating_toolbar.ex`
- **Show** target picker as a separate "Link to" section for ALL zone types — it is orthogonal to action_type
- **Remove** `event` and `navigate` from the action_type dropdown options
- **Update** `handle_update_zone_action_type` in `element_handlers.ex` — currently resets `action_data` on type switch, which is correct, but must NOT touch `target_type`/`target_id`

**Files:**
- `lib/storyarn_web/live/scene_live/components/floating_toolbar.ex` — remove conditional, restructure UI
- `lib/storyarn_web/live/scene_live/handlers/element_handlers.ex` — update `handle_update_zone_action_type`

### 2.3 Data migration for existing zones

- **`navigate` zones** → set `action_type: "none"`. These already use `target_type/target_id` for their link behavior — that data is preserved.
- **`event` zones** → set `action_type: "none"`.
  - If the zone already has `target_type: "flow"` set → done, just change action_type
  - If the zone was connected to an interaction node via event_name → logged for manual review (see Phase 7 for the full interaction node migration)
- **Migration script:** Mix task with dry-run support. NOT an Ecto migration — data transformation logic shouldn't live in migrations.

**Files:**
- `lib/mix/tasks/migrate_zone_action_types.ex` — data migration Mix task
- `lib/storyarn/maps/map_zone.ex`

### 2.4 Update zone queries

- **Update** `ZoneCrud.list_event_zones/1` — queries for `action_type == "event"`, will return empty after migration. Consider deprecating or rewriting to check `target_type` instead.
- **Update** `ZoneCrud.list_actionable_zones/1` — queries for `action_type != "navigate"`, needs to change to `action_type != "none"` or be rewritten.

**Files:**
- `lib/storyarn/maps/zone_crud.ex`

### Verification
```bash
mix ecto.migrate
mix compile --warnings-as-errors
mix test
# Manual: Create a zone with action_type "instruction" AND target_type "flow" — verify both are saved independently
# Manual: Verify existing navigate zones still show their target link after migration
```

---

## Phase 3: Condition Support for Zones and Pins

**Goal:** Zones and pins can have visibility conditions. Editor UI for configuring conditions.

### 3.1 Condition evaluation utility for map elements

- **Create** `Storyarn.Maps.ConditionEvaluator` that wraps `ConditionEval.evaluate/2` for map context
- **Function:** `evaluate_element_condition(condition, variables) :: :visible | :disabled | :hidden`
  - `nil` condition → `:visible`
  - Condition passes → `:visible`
  - Condition fails + effect "hide" → `:hidden`
  - Condition fails + effect "disable" → `:disabled`

**Files:**
- `lib/storyarn/maps/condition_evaluator.ex`

### 3.2 Condition editor in zone/pin config sidebar

- **Reuse** the existing `<.condition_builder>` component from `StoryarnWeb.Components.ConditionBuilder`
- **Add** condition section to zone config panel (below action_type)
- **Add** condition section to pin config panel
- **Add** `condition_effect` toggle (hide/disable)

**Files:**
- `lib/storyarn_web/live/scene_live/` — zone/pin config components
- Existing: `lib/storyarn_web/components/condition_builder.ex`

### 3.3 Variable reference tracking for conditions

- **Extend** `VariableReferenceTracker` to track zone/pin conditions as reads
- **Wire** condition changes into the tracker

**Files:**
- `lib/storyarn/flows/variable_reference_tracker.ex`

### Verification
```bash
mix compile --warnings-as-errors
mix test
```

---

## Phase 4: Exploration Mode Player

**Goal:** A new map player that renders the map with interactive zones/pins. The core of the new system.

### 4.1 Exploration LiveView

- **New route:** `/workspaces/:ws/projects/:ps/maps/:id/play`
- **New LiveView:** `StoryarnWeb.SceneLive.ExplorationLive`
- **Mount:**
  1. Load map with zones, pins, layers, background asset
  2. Load project variables via `VariableHelpers.build_variables(project_id)`
  3. Evaluate zone/pin conditions against variables (using `ConditionEvaluator` from Phase 3)
  4. Serialize map data for the JS hook — **reuse** existing `Serializer.build_map_data/1`, `serialize_zone/1`, `serialize_pin/1`, and `background_url/1` from `lib/storyarn_web/live/scene_live/helpers/serializer.ex`
- **Socket assigns:** `map`, `project`, `zones` (with visibility), `pins` (with visibility), `variables` (local state), `active_flow` (nil initially)

**Files:**
- `lib/storyarn_web/live/scene_live/exploration_live.ex`
- `lib/storyarn_web/router.ex`
- Existing (reuse): `lib/storyarn_web/live/scene_live/helpers/serializer.ex`

### 4.2 Exploration JS hook

- **New hook:** `ExplorationPlayer` in `assets/js/hooks/exploration_player.js`
- **Extend** the InteractionPlayer approach (pure DOM, no Leaflet):
  - Render map background image with aspect ratio
  - Render zones as polygon clip-path overlays (reuse InteractionPlayer logic)
  - **NEW:** Render pins as positioned markers (icon + label)
  - Condition states: visible (normal), disabled (dimmed + not clickable), hidden (not rendered)
  - Click handlers push events to server
- **Events pushed:**
  - `exploration_zone_click` → `{zone_id, action_type, target_type, target_id}`
  - `exploration_pin_click` → `{pin_id, action_type, target_type, target_id}`
  - `exploration_instruction` → `{assignments, source}` (for instruction zones/pins)

**Files:**
- `assets/js/hooks/exploration_player.js`
- `assets/js/hooks/index.js` (register hook)

### 4.3 Exploration event handlers

- **`handle_event("exploration_instruction", params, socket)`**: Execute instruction, update local variables, re-evaluate conditions, push updated state
- **`handle_event("exploration_zone_click", params, socket)`**: If zone has `target_type: "flow"` → transition to flow mode. If `target_type: "map"` → scene transition.
- **`handle_event("exploration_pin_click", params, socket)`**: Same logic as zone click.
- **Re-evaluation:** After any state change, re-evaluate ALL zone/pin conditions and push updated visibility

**Files:**
- `lib/storyarn_web/live/scene_live/exploration_live.ex`

### 4.4 Play button on maps

- **Add** "Play" button to map editor toolbar
- **Links to** `/workspaces/:ws/projects/:ps/maps/:id/play`

**Files:**
- `lib/storyarn_web/live/scene_live/show.ex` — toolbar

### Verification
```bash
mix compile --warnings-as-errors
mix test
# Manual: Open map editor → click Play → see map in exploration mode
# Manual: Click zone with instruction → variable updates → conditions re-evaluate
```

---

## Phase 5: Flow-Exploration Integration

**Goal:** Launch flows from exploration, show map backdrop during flow mode, return to exploration after flow exit.

### 5.0 Extract shared FlowRunner module

ExplorationLive needs to handle all flow events (`choose_response`, `continue`, `go_back`, subflow jumps/returns) — the same logic that already exists in `PlayerLive`. To avoid duplicating ~200 lines of flow execution code:

- **Extract** `StoryarnWeb.FlowLive.FlowRunner` — a shared module encapsulating flow execution logic:
  - `init_flow(flow_id, variables, project_id)` → loads nodes/connections, initializes engine, steps to interactive
  - `handle_continue(engine_state, nodes, connections)` → steps forward
  - `handle_choose_response(engine_state, response_id, connections)` → selects response, steps forward
  - `handle_go_back(engine_state)` → step back
  - `handle_flow_jump(engine_state, flow_id, nodes, connections)` → push context, load subflow, step
  - `handle_flow_return(engine_state)` → pop context, advance past subflow node, step
  - `build_slide(engine_state, nodes, sheets_map, project_id)` → builds slide for current node
- **Refactor** `PlayerLive` to use `FlowRunner` instead of inline logic
- **ExplorationLive** also uses `FlowRunner` for all flow execution within exploration

**Files:**
- `lib/storyarn_web/live/flow_live/flow_runner.ex` (new)
- `lib/storyarn_web/live/flow_live/player_live.ex` (refactor to use FlowRunner)

### 5.1 Launch flow from exploration

- **When** a zone/pin with `target_type: "flow"` is clicked in exploration mode:
  1. If the element has `action_type: "instruction"` → execute instruction first, update local variables
  2. Call `FlowRunner.init_flow(target_flow_id, local_variables, project_id)`
  3. Transition the LiveView to "flow mode" — show dialogue/choice UI on top of map
- **Note:** This is NOT a subflow — no call stack push. The flow is a top-level invocation from exploration. The call stack is only used for subflow jumps WITHIN the triggered flow.

- **Socket assigns change:** `active_flow` goes from `nil` to `%{flow_id, engine_state, nodes, connections, slide, sheets_map}`
- **UI:** Map stays visible but dimmed. Flow dialogue UI overlays on top.

**Files:**
- `lib/storyarn_web/live/scene_live/exploration_live.ex`
- New component: `lib/storyarn_web/live/scene_live/components/exploration_flow_overlay.ex`

### 5.2 Map backdrop during flow dialogue

- **Render** the map as a dimmed background behind the dialogue slide
- **Reuse** the dialogue slide component from the existing flow player (`player_dialogue.ex`)
- **CSS:** Map at z-index 0 (dimmed), dialogue overlay at z-index 10

**Files:**
- `lib/storyarn_web/live/scene_live/exploration_live.ex` — template
- `assets/css/exploration.css` — overlay styles

### 5.3 Flow execution within exploration

- **Delegate** all flow events to `FlowRunner`:
  - `"choose_response"` → `FlowRunner.handle_choose_response/3`
  - `"continue"` → `FlowRunner.handle_continue/3`
  - `"go_back"` → `FlowRunner.handle_go_back/1`
- **Handle** `FlowRunner` return values: `:ok` (update slide), `:flow_jump` (delegate to FlowRunner), `:flow_return` (delegate), `:finished` (return to exploration)
- **Slide building:** Via `FlowRunner.build_slide/4`

**Files:**
- `lib/storyarn_web/live/scene_live/exploration_live.ex` — event handlers

### 5.4 Exit node targeting

Exit nodes currently have three `exit_mode` values: `"terminal"`, `"flow_reference"`, `"caller_return"`. The new `target_type`/`target_id` fields interact with `exit_mode` as follows:

| `exit_mode` | `target_type` | Behavior |
|---|---|---|
| `terminal` | `nil` (default) | Flow finished. If in exploration → return to map. If standalone → outcome slide. **Current behavior preserved.** |
| `terminal` | `map` | Flow finished with scene transition. Exploration resumes on target map. |
| `terminal` | `flow` | Flow finished, chain to target flow (new top-level invocation, NOT a subflow). |
| `flow_reference` | ignored | Jump to referenced flow. **Current behavior unchanged** — `target_type` is irrelevant here. |
| `caller_return` | ignored | Return to calling flow via call stack. **Current behavior unchanged** — `target_type` is irrelevant here. |

**Implementation:**
- `target_type`/`target_id` are ONLY evaluated when `exit_mode == "terminal"` (or defaults to terminal)
- **Do NOT change the Engine return type.** Instead, store transition info in the State struct:
  - Add `exit_transition` field to `State`: `nil` (default), `%{type: :map, id: integer()}`, or `%{type: :flow, id: integer()}`
  - `ExitEvaluator` sets `state.exit_transition` from exit node data before returning `{:finished, state}`
  - All existing `{:finished, state}` pattern matches remain valid — callers read `state.exit_transition` to decide post-finish behavior
- **Update** exit node config sidebar: show `target_type`/`target_id` picker ONLY when `exit_mode == "terminal"`

**Files:**
- `lib/storyarn/flows/evaluator/state.ex` — add `exit_transition` field
- `lib/storyarn/flows/evaluator/node_evaluators/exit_evaluator.ex` — read target from node data, set `state.exit_transition`
- `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex` — UI for target picker (conditional on terminal mode)

### 5.5 Return to exploration after flow exit

- **When** the flow engine returns `{:finished, state}` and `state.exit_transition == nil`:
  1. Transfer `state.variables` back to exploration's local variable state
  2. Clear `active_flow` assign
  3. Re-evaluate all zone/pin conditions with updated variables
  4. Push updated map state to JS hook
  5. UI transitions back to exploration mode

- **When** `state.exit_transition == %{type: :map, id: scene_id}`:
  1. Transfer variable state
  2. Load the target map
  3. Re-initialize exploration on the new map (scene transition)

- **When** `state.exit_transition == %{type: :flow, id: flow_id}`:
  1. Transfer variable state
  2. Call `FlowRunner.init_flow(flow_id, variables, project_id)` — chain to next flow
  3. Stay in flow mode with new flow

**Files:**
- `lib/storyarn_web/live/scene_live/exploration_live.ex`

### Verification
```bash
mix compile --warnings-as-errors
mix test
# Manual: Exploration → click NPC pin → dialogue plays with map behind
# Manual: Dialogue ends (no target) → back to exploration with updated conditions
# Manual: Exit with target:map → scene transition to new map
# Manual: Exit with target:flow → chains to next flow seamlessly
```

---

## Phase 6: `scene_scene_id` Integration

**Goal:** Flows with `scene_scene_id` show the map as backdrop. Inheritance works.

### 6.1 `scene_scene_id` inheritance resolution

- **Create** `Storyarn.Flows.SceneResolver` module
- **Function:** `resolve_scene_map(flow, opts \\ [])`:
  1. If `flow.scene_scene_id` is set → return it (authoritative)
  2. If `opts[:caller_scene_scene_id]` is set → return it (runtime inheritance)
  3. Walk up `parent_id` chain looking for `scene_scene_id` → return first found
  4. Return `nil`
- **Preload optimization:** When loading a flow for the player, preload the scene resolution chain in a single query

**Files:**
- `lib/storyarn/flows/scene_resolver.ex`

### 6.2 Flow editor UI for `scene_scene_id`

- **Add** a "Scene Map" field to flow settings/config panel
- **Searchable select** to pick from project maps
- **Show** inherited scene (with "inherited from: X" indicator)
- **Allow** clearing (nil → inherits from parent)

**Files:**
- `lib/storyarn_web/live/flow_live/` — flow settings component

### 6.3 Map backdrop in flow player

- **Modify** `PlayerLive` mount to resolve `scene_scene_id` for the flow
- **If resolved:** Load map data (background image, dimensions)
- **Render** map as background behind dialogue slides
- **CSS:** Map dimmed at z-index 0, dialogue at z-index 10 (same as Phase 5)

**Files:**
- `lib/storyarn_web/live/flow_live/player_live.ex`
- `lib/storyarn_web/live/flow_live/player/components/player_slide.ex` — add backdrop layer

### 6.4 Cross-flow scene transitions

Scene resolution happens in the **LiveView layer**, not in the engine. The engine is pure functional and has no concept of `scene_scene_id`. The LiveView detects scene changes after the engine reports a `flow_jump` or `flow_return`.

- **When** `FlowRunner` handles a `flow_jump` to a subflow:
  1. LiveView resolves `scene_scene_id` for the target subflow via `SceneResolver.resolve_scene_map/2` (passing `caller_scene_scene_id` from current context)
  2. If the resolved scene differs from the current backdrop → push scene transition event to frontend
  3. Frontend loads new map background
- **When** `FlowRunner` handles a `flow_return`:
  1. LiveView restores the parent flow's resolved scene
  2. If different from subflow's scene → push scene transition event (revert)
- **Track** resolved scene in socket assigns: `current_scene_scene_id` updated on every flow jump/return

**Files:**
- `lib/storyarn_web/live/flow_live/player_live.ex` — subflow handling, scene tracking
- `lib/storyarn_web/live/flow_live/flow_runner.ex` — return scene context alongside flow state
- `assets/js/hooks/` — handle scene transition event

### Verification
```bash
mix compile --warnings-as-errors
mix test
# Manual: Set scene_scene_id on flow → Play flow → see map behind dialogue
# Manual: Child flow with different scene_scene_id → background changes
# Manual: Return from child flow → background reverts
```

---

## Phase 7: Interaction Node Deprecation

**Goal:** Remove interaction nodes. Migrate existing data. Clean up code.

### 7.1 Data migration (semi-manual — highest risk item)

**Why this is hard:** Interaction nodes sit INSIDE a flow. Event zones on the referenced map are connected to the interaction node's output pins — each event zone connects to a DIFFERENT branch of the same flow. In the new model, a zone with `target_type: "flow"` launches the ENTIRE flow from entry. You can't simply point zones at the parent flow — that restarts from entry, not from the specific branch.

**Automated (safe) part:**
- **For each existing interaction node:**
  1. Get `scene_id` from node data
  2. Set `scene_scene_id = scene_id` on the node's parent flow (if not already set)
  3. Record the migration for user notification

**Semi-manual (requires designer review) part:**
- **For each interaction node with event zone connections:**
  1. Identify what nodes the event zone outputs connect to
  2. Generate a report showing: interaction node → zone → connected branch
  3. The designer must decide how to restructure:
     - **Option A:** Split the flow — extract each post-interaction branch into a separate child flow, then point zones to those child flows
     - **Option B:** Restructure as hub-based — replace the interaction node with a hub, create entry points for each zone, connect them
     - **Option C:** Keep the flow as-is and use the exploration model (zones trigger the parent flow, which must be restructured to start with a condition/hub that routes to the correct branch)
  4. Provide a UI tool (or Mix task) that assists with the split, but do NOT auto-transform flow graphs

**Tooling:**
- Mix task with `--dry-run` that generates a migration report (JSON/Markdown) per project
- Report lists every interaction node, its map, its event zones, and the connected branches
- The designer reviews the report and decides on restructuring approach per node

**Files:**
- `lib/mix/tasks/migrate_interaction_nodes.ex` — report generation + safe automated part
- Migration guide documentation for designers

### 7.2 Remove interaction node from UI

- **Remove** from context menu in flow editor (`context_menu_items.js`)
- **Remove** from node type registry (`node_type_registry.ex`)
- **Remove** from node config sidebar (`nodes/interaction/`)
- **Keep** the schema type in FlowNode for backward compatibility (soft removal — the type can exist in DB but won't be creatable)

**Files:**
- `assets/js/flow_canvas/context_menu_items.js`
- `lib/storyarn_web/live/flow_live/node_type_registry.ex`
- `lib/storyarn_web/live/flow_live/nodes/interaction/` — archive or remove

### 7.3 Remove interaction handling from player engine

- **Remove** `interaction` from `@non_interactive_types` check (it was interactive)
- **Remove** `InteractionEvaluator` calls from engine step function
- **Remove** `interaction_zone_instruction` and `interaction_zone_event` handlers from `PlayerLive`
- **Remove** `:interaction` slide type from `Slide.build/4`
- **Remove** the `InteractionPlayer` hook JS file — `ExplorationPlayer` (Phase 4) fully replaces it. If Phase 7 runs after Phase 4 (as the dependency chain requires), the replacement already exists.

**Files:**
- `lib/storyarn/flows/evaluator/engine.ex`
- `lib/storyarn_web/live/flow_live/player_live.ex`
- `lib/storyarn_web/live/flow_live/player/slide.ex`
- `lib/storyarn_web/live/flow_live/player/components/player_interaction.ex` — remove
- `lib/storyarn_web/live/flow_live/player/components/player_slide.ex` — remove interaction case

### 7.4 Update stress test documentation

- **Update** `docs/stress_test/issues.md` if needed
- **Update** `SCENE_INTERACTION_MODEL.md` to mark implementation as done

### Verification
```bash
mix compile --warnings-as-errors
mix test
# Manual: Verify no interaction nodes in flow context menu
# Manual: Verify existing flows with interaction nodes still load (graceful degradation)
# Manual: Full Torment stress test works via map exploration
```

---

## Dependencies Between Phases

```
Phase 1 (Schema) ──→ Phase 2 (Zone Cleanup) ──→ Phase 3 (Conditions)
                                                        │
                                                        ▼
                                                 Phase 4 (Exploration Player)
                                                        │
                                                        ▼
Phase 1 (Schema) ──────────────────────────→ Phase 5 (Flow-Exploration Integration)
                                                        │
                                                        ▼
                                              Phase 6 (scene_scene_id Integration)
                                                        │
                                                        ▼
                                              Phase 7 (Interaction Deprecation)
```

Phases 1-3 can be done without touching the player.
Phase 4 delivers standalone exploration mode (valuable on its own).
Phase 5 connects exploration to flows (the core feature).
Phase 6 adds backdrop support for flow-only playback.
Phase 7 is cleanup — only after everything else works.

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Interaction node migration requires flow restructuring** | **High** | Semi-manual migration with tooling support. Auto-generate reports, designer decides restructuring approach per node. Cannot be fully automated. |
| Zone `maybe_clear_target` decoupling breaks existing zones | Medium | Three-layer lockstep change (changeset + UI + JS). Test with existing zone data before/after. Data migration handles `navigate` → `none` conversion. |
| Zone default `action_type` change (`navigate` → `none`) | Medium | Data migration converts all existing `navigate` zones before changeset validation change. New zones get `none` as default. |
| Zone data migration breaks existing zones | Medium | Dry-run migration script. Keep old values readable in DB. |
| Exploration mode performance with many zones/pins | Low | Lazy condition evaluation. Only evaluate visible viewport. |
| State sync between exploration and flow engine | Low | Single variable state object passed by value. No shared mutable state. `FlowRunner` returns final `state.variables` on finish. |
| Interaction node deprecation breaks existing projects | Low | Soft removal: type exists in DB but not creatable. Graceful fallback in engine (pass-through for unknown types). |
| Exit node targeting — engine contract | **None** | Transition info stored in `State.exit_transition` field, NOT in return tuple. All existing `{:finished, state}` pattern matches remain valid. |
| Code duplication between PlayerLive and ExplorationLive | Medium | `FlowRunner` module (Phase 5.0) extracts shared logic. Both LiveViews delegate to it. |

---

## Estimated Scope per Phase

| Phase | Schema changes | UI changes | Engine changes | New files |
|-------|---------------|------------|----------------|-----------|
| 1 | 3 migrations | None | None | ~5 |
| 2 | 1 migration + Mix task | Zone config (toolbar + handlers) | None | ~3 |
| 3 | None | Condition UI | None | ~2 |
| 4 | None | New LiveView + Hook | None | ~4 |
| 5 | None | Flow overlay | State.exit_transition + FlowRunner extraction | ~4 |
| 6 | None | Flow settings, backdrop | Scene resolver (LiveView layer) | ~3 |
| 7 | None | Remove interaction | Remove evaluator | ~1 (migration tooling) + removals |

---

*Plan created: 2026-02-23*
*Last reviewed: 2026-02-23 — applied 10 fixes from critical review*
*Concept: `docs/concepts/SCENE_INTERACTION_MODEL.md`*
*Related: `docs/stress_test/issues.md`, `IMPLEMENTATION_PLAN.md`*
