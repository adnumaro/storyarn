# Epic 2 — Living World

> Make the scene feel alive with autonomous behaviors and atmosphere

## Context

After Epic 1, the player can explore a scene: move their character, collect items, and interact with the environment. But the world is **static** — nothing happens unless the player acts. This epic adds **autonomous life**: NPCs that move, companions that comment, sounds that shift with position. The scene becomes a place that **exists independently of the player**.

Each feature is independent and delivers standalone value.

---

## Feature 1: NPC Patrol Routes

### What
NPCs (non-playable pins) automatically move along their defined connections (paths) in exploration mode. A guard patrols between waypoints, a merchant walks between market stalls, an animal roams its territory.

- Connections from a pin define its patrol route
- Movement is automatic and continuous (loop or ping-pong)
- NPCs remain clickable/interactable during patrol
- NPCs respect visibility conditions (appear/disappear based on variables)

### Why (standalone value)
A single patrolling guard transforms a static map into a living scene. The player perceives the world as active, not frozen. This creates emergent gameplay feel: timing your movement to avoid a patrol, catching a merchant at their stall.

### Key concepts
- **Patrol modes**: `loop` (A→B→C→A→B→C), `ping_pong` (A→B→C→B→A), `one_way` (A→B→C→stop)
- **Speed**: per-pin or per-connection configurable
- **Pause at pins**: optional dwell time at each waypoint (guard stops for 3 seconds at each post)
- **Route definition**: uses existing connections + waypoints. The connection order from a pin defines the route sequence
- **Interruption**: if the player interacts with a patrolling NPC (clicks to talk), the NPC pauses. Resumes after the interaction

### Schema changes
- `ScenePin`: add `patrol_mode` (string enum: `none` | `loop` | `ping_pong` | `one_way`, default: `none`)
- `ScenePin`: add `patrol_speed` (float, default: 1.0 — multiplier)
- `ScenePin`: add `patrol_pause_ms` (integer, default: 0 — pause at each waypoint in ms)

### Design considerations
- Route defined by outgoing connections in position order — no new data structure needed
- NPC rendering during movement: smooth interpolation along connection waypoints
- Multiple NPCs can patrol simultaneously — each independent
- Performance: use requestAnimationFrame, not setInterval. Pause animation when tab is not visible
- Pin interactions (click → flow) work the same whether the NPC is moving or stationary

### Acceptance criteria
- [ ] Pin editor shows patrol mode, speed, and pause settings
- [ ] In exploration: NPC pins with patrol routes move automatically
- [ ] Movement follows connection waypoints smoothly
- [ ] NPCs pause at waypoints for configured duration
- [ ] Loop, ping-pong, and one-way modes work correctly
- [ ] Clicking a patrolling NPC still triggers its action/flow
- [ ] NPC pauses patrol during interaction, resumes after
- [ ] Condition-hidden NPCs don't patrol (or disappear mid-patrol gracefully)

---

## Feature 2: Ambient Flows (Morte-style)

### What
Flows that execute in parallel with exploration, without blocking player interaction. Dialogue lines appear as floating speech bubbles over characters while the player continues moving and interacting.

Inspired by Planescape: Torment, where Morte comments constantly as you explore — reacting to locations, events, and player actions without ever taking control away.

### Why (standalone value)
This adds a **narrative layer** to exploration that doesn't exist in any competing tool. The designer can create a living narrator, companion commentary, environmental storytelling — all running in the background while the player plays.

### Blocks

This feature is split into 4 incremental blocks. Each block is shippable and builds on the previous one.

---

#### Block A: Speech Bubbles (visual foundation)

**What:** A generic mechanism to show a text bubble above any pin. No flow engine, no triggers — just `push_event("show_bubble", ...)` from the server and JS renders/dismisses it.

**Why first:** Every subsequent block needs this rendering primitive. Building it standalone lets us test the visual independently and reuse it for non-ambient purposes too (e.g. tutorial hints, NPC barks).

**Scope:**
- JS: `showBubble({ pinId, text, speaker, duration, position })` — creates a floating div above the pin element, auto-dismisses after `duration` ms
- Bubble follows pin position (works with patrol movement via polling or MutationObserver on pin style)
- CSS animation: fade-in, fade-out
- Queue: if a bubble is already showing on a pin, replace it (no stacking)
- Server helper: `push_bubble(socket, pin_id, text, opts)` — convenience wrapper

**Key files:**
- `assets/js/hooks/exploration_player.js` — `showBubble`, `dismissBubble` methods + `handleEvent("show_bubble")`
- `assets/css/exploration.css` — bubble styles
- `exploration_live.ex` — `push_bubble/4` helper

**Acceptance criteria:**
- [ ] `push_event("show_bubble", %{pin_id, text, duration})` renders a bubble above the pin
- [ ] Bubble auto-dismisses after duration
- [ ] Bubble follows pin if it moves (patrol)
- [ ] New bubble on same pin replaces existing one
- [ ] Bubble has fade-in/fade-out animation

---

#### Block B: Ambient Flow Schema + Editor UI

**What:** The data model for linking flows to scenes as ambient, and the editor UI to configure them. No runtime execution yet.

**Schema — `SceneAmbientFlow`:**
- `scene_id` (FK), `flow_id` (FK)
- `trigger_type`: `on_enter` (only trigger type for now — others added in Block D)
- `enabled` (boolean, default true)
- `position` (integer — ordering)

**Why minimal schema:** Skip `trigger_config`, `priority`, and advanced trigger types. `on_enter` is the only trigger — it fires when the scene loads. This covers 80% of ambient flow use cases (companion comments on entering a room).

**Editor UI in scene settings or element panel:**
- List of ambient flows linked to this scene
- Add flow (searchable select from project flows)
- Reorder (drag or arrows)
- Remove
- Enable/disable toggle

**Key files:**
- `priv/repo/migrations/..._create_scene_ambient_flows.exs`
- `lib/storyarn/scenes/scene_ambient_flow.ex` — schema
- `lib/storyarn/scenes/ambient_flow_crud.ex` — CRUD submodule
- `lib/storyarn/scenes.ex` — facade delegates
- Scene editor UI (settings section or dedicated panel)

**Acceptance criteria:**
- [ ] Migration + schema with validations
- [ ] CRUD: list/create/update/delete ambient flow bindings
- [ ] Editor UI: add, remove, reorder, enable/disable ambient flows for a scene
- [ ] Unique constraint: same flow can't be linked twice to the same scene

---

#### Block C: Ambient Flow Execution (on_enter)

**What:** When entering exploration mode, enabled ambient flows execute automatically in the background. The PlayerEngine steps through the flow linearly, rendering each dialogue node as a speech bubble (Block A) on the appropriate pin, auto-advancing after a timer.

**Runtime flow:**
1. On mount, load enabled ambient flows for the scene (ordered by position)
2. For each: init PlayerEngine, step to first interactive node
3. If dialogue node: find the pin whose `sheet_id` matches `speaker_sheet_id` → show bubble on that pin
4. Auto-advance after `duration` (based on text length: ~60 words/min, minimum 2s, max 8s)
5. Continue stepping until flow ends
6. If condition node: evaluate normally, follow the matching branch
7. If instruction node: execute (update variables), continue stepping
8. Non-dialogue nodes (hub, jump, etc.): skip silently, continue stepping

**Constraints (keep it simple):**
- **One ambient flow at a time** — flows execute sequentially, not in parallel. No priority queue needed
- **Linear only** — dialogue responses are ignored (auto-continue). The flow is treated as a linear narration
- **No speaker match = subtitle** — if no pin matches `speaker_sheet_id`, show bubble as a floating subtitle at bottom center
- **Variables shared** — ambient flow reads/writes the same `variables` map as the exploration session

**Pause/resume with full flows:**
- When a full flow starts (`init_flow`): pause ambient flow (save engine state, dismiss active bubble)
- When full flow ends (`return_to_exploration`): resume ambient flow from where it left off
- Reuse existing `patrol_pause`/`patrol_resume` pattern — add `ambient_pause`/`ambient_resume` or bundle into a single `exploration_pause`/`exploration_resume`

**Key files:**
- `exploration_live.ex` — ambient flow lifecycle (init, step, pause, resume), new assigns
- `assets/js/hooks/exploration_player.js` — reuses `showBubble` from Block A

**Acceptance criteria:**
- [ ] Ambient flows auto-start on scene mount (on_enter)
- [ ] Dialogue nodes render as speech bubbles on the matching pin
- [ ] Auto-advance based on text length
- [ ] Condition/instruction nodes execute silently
- [ ] Ambient flow pauses during full flow, resumes after
- [ ] Player can move and interact while ambient flow runs
- [ ] Multiple ambient flows play sequentially (one finishes, next starts)
- [ ] Variables modified by ambient flows are reflected in exploration state

---

#### Block D: Additional Triggers + Priority

**What:** Extend the trigger system beyond `on_enter`. Add `timed`, `on_event`, and `one_shot` trigger types. Add priority field for ordering when multiple flows trigger simultaneously.

**Schema changes:**
- `SceneAmbientFlow`: add `trigger_config` (jsonb, default `%{}`)
- `SceneAmbientFlow`: add `priority` (integer, default 0)

**Trigger types:**
- `on_enter` — fires on scene load (existing)
- `timed` — fires every N ms (`trigger_config: {"interval_ms": 30000}`). Useful for periodic companion comments
- `on_event` — fires when a variable changes (`trigger_config: {"variable_ref": "mc.jaime.health"}`). Companion reacts to taking damage
- `one_shot` — fires once per session, tracked via `completed_ambient_ids` set in socket assigns (same pattern as `collected_ids`)

**Priority:** When multiple flows trigger at the same time, higher priority plays first. Others queue behind.

**Editor UI updates:**
- Trigger type select (on_enter / timed / on_event / one_shot)
- Conditional fields based on trigger type (interval input, variable select)
- Priority input

**Acceptance criteria:**
- [ ] `timed` trigger fires periodically
- [ ] `on_event` trigger fires when the specified variable changes
- [ ] `one_shot` trigger fires once and is marked completed for the session
- [ ] Priority ordering when multiple flows trigger simultaneously
- [ ] Editor UI for trigger configuration

---

## Feature 3: Audio Zones with Distance Attenuation

### What
Zones with associated audio assets that play spatially: volume attenuates based on the player character's distance from the zone center. Multiple audio zones blend naturally — walking between a tavern and a river, both sounds mix at appropriate volumes.

### Why (standalone value)
Sound is the most underestimated tool for immersion. A silent map feels dead even with moving NPCs. Add tavern chatter that fades as you walk away, forest ambience that swells near the treeline, and suddenly the scene has **atmosphere**. This is a massive immersion upgrade with relatively simple implementation (Web Audio API handles the math).

### Key concepts
- **Audio zone**: a zone with an `audio_asset_id` + `audio_radius` (how far the sound reaches, as % of scene)
- **Attenuation**: `volume = max(0, 1 - (distance / radius))` — linear falloff (or configurable curve)
- **Blending**: multiple audio zones active simultaneously, each at their calculated volume
- **Loop**: most ambient audio loops continuously
- **Player position**: volume calculated from leader pin position to zone center

### Schema changes
- `SceneZone`: add `audio_asset_id` (FK to Asset, nullable)
- `SceneZone`: add `audio_radius` (float, 0-100 as % of scene diagonal, default: 20)
- `SceneZone`: add `audio_volume` (float, 0-1, default: 1.0 — max volume at center)
- `SceneZone`: add `audio_loop` (boolean, default: true)

### Design considerations
- Use Web Audio API for spatial mixing — `GainNode` per audio source, update gain on player movement
- Audio context must be started after user gesture (browser requirement) — start on first click
- Performance: update volumes on player movement (throttled, not every frame)
- Preload audio assets on scene enter to avoid playback delays
- Visual in edit mode: show audio radius as a circle overlay centered on zone centroid
- Mute button in exploration toolbar
- Consider: global scene background audio (no attenuation) as a scene-level setting

### Acceptance criteria
- [ ] Zone editor: audio asset picker + radius + volume + loop settings
- [ ] Edit mode: visual radius indicator for audio zones
- [ ] Exploration: audio plays when player is within radius
- [ ] Volume attenuates with distance from zone center
- [ ] Multiple audio zones blend simultaneously
- [ ] Audio loops seamlessly when configured
- [ ] Mute/unmute control in exploration toolbar
- [ ] Audio starts after first user interaction (browser policy compliance)
- [ ] Audio stops when leaving exploration mode

---

## Feature 4: Fog of War / Discovery Zones

### What
Zones that act as **triggers** — when the player character enters the zone, an instruction executes automatically. Combined with visibility conditions on other elements, this creates fog of war: areas are hidden until "discovered".

### Why (standalone value)
Progressive revelation is fundamental to exploration. Entering an unknown room and seeing it "unlock" on the map creates a sense of discovery. This works for dungeon crawlers, mystery games, open-world exploration — any genre where not everything is visible from the start.

### Key concepts
- **Trigger zone**: a zone with `trigger_on_enter: true` + an instruction
- **One-shot vs repeatable**: trigger fires once (set `area.north_discovered = true`) or every time (damage zone: lose 1 HP per entry)
- **Fog rendering**: other zones/pins with condition `area.north_discovered == true` appear/disappear based on discovery
- **Visual fog**: optionally render undiscovered areas as darkened/blurred overlay (CSS filter on undiscovered regions)
- **Distinction from click zones**: trigger zones fire on **entry** (character position intersects polygon), not on click

### Schema changes
- `SceneZone`: add `trigger_on_enter` (boolean, default: false)
- `SceneZone`: add `trigger_once` (boolean, default: true)
- Reuses existing `action_type: instruction` + `action_data` for the trigger action

### Design considerations
- Entry detection: check point-in-polygon whenever player position changes
- "Entry" = player wasn't inside last tick, now is inside (edge trigger, not level trigger) — unless repeatable
- Trigger once: needs state tracking. With persistence (Epic 1.4), this is saved. Without, it's session-scoped
- Visual fog: could be a CSS overlay with clip-path holes cut for discovered areas. Or simpler: just hide elements via conditions (designer controls what's visible)
- Combination with audio zones: entering a cave triggers discovery AND starts cave ambience
- Performance: don't check all zones every frame — only check when player moves, and use bounding box pre-filter

### Acceptance criteria
- [ ] Zone editor: "Trigger on enter" toggle + "One-shot" toggle
- [ ] Trigger zones with instructions execute when player enters
- [ ] One-shot triggers only fire once per session
- [ ] One-shot state persists across saves (with Epic 1.4)
- [ ] Other elements with visibility conditions react to trigger-set variables
- [ ] Trigger zones can be visually distinct in edit mode
- [ ] Entry detection is edge-triggered (fires once per entry, not continuously)

---

## Feature 5: Visual Interaction Indicators

### What
Visual cues that communicate what elements are interactable and what type of interaction they offer. Cursor changes, floating icons, and highlight effects.

### Why (standalone value)
Without indicators, the player doesn't know what's clickable. They hover randomly hoping to find interactions (the "pixel hunting" problem of classic Point & Click games). Good indicators make exploration intuitive and frustration-free.

### Key concepts
- **Cursor changes**: default (arrow), move (crosshair on walkable area), interact (hand on clickable zone), talk (speech bubble on NPC pin), examine (eye on display zone)
- **Floating icons**: small icon above interactable elements (configurable: show always, show on hover, never)
- **Highlight on hover**: zone border glow or slight color shift when hovering an interactable zone
- **Interaction type mapping**: derive cursor/icon from element configuration:
  - Zone with `target_type: flow` → speech/talk icon
  - Zone with `action_type: collection` → hand/grab icon
  - Zone with `action_type: instruction` → gear/action icon
  - Zone with `action_type: display` → eye icon
  - Pin with `target_type: flow` → speech icon
  - Walkable zone → crosshair cursor

### Schema changes
- Likely none — indicators are derived from existing data
- Optional: `Scene` add `show_interaction_icons` (boolean, default: true) for global toggle

### Design considerations
- Icons should be subtle — don't clutter the scene
- Consider a "highlight all interactables" hotkey (Tab key, like in many CRPGs) that briefly shows all interactive elements
- Disabled elements (condition_effect: disable) show a different indicator (lock icon, grayed out)
- Icons use Lucide icon set (consistent with rest of Storyarn)
- Mobile/touch: long-press to show indicators since there's no hover

### Acceptance criteria
- [ ] Cursor changes based on what's under it
- [ ] Hovering interactable zones shows subtle highlight
- [ ] Floating icons appear above interactable elements (configurable)
- [ ] "Highlight all" hotkey (Tab) briefly reveals all interactable elements
- [ ] Disabled elements show distinct indicator
- [ ] Icons match interaction type (talk, grab, examine, etc.)
- [ ] Scene-level toggle to enable/disable interaction indicators
