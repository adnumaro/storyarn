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
Flows that execute in parallel with exploration, without blocking player interaction. Dialogue lines appear as floating subtitles or speech bubbles over characters while the player continues moving and interacting.

Inspired by Planescape: Torment, where Morte comments constantly as you explore — reacting to locations, events, and player actions without ever taking control away.

### Why (standalone value)
This adds a **narrative layer** to exploration that doesn't exist in any competing tool. The designer can create a living narrator, companion commentary, environmental storytelling — all running in the background while the player plays.

### Key concepts
- **Ambient flow binding**: a flow is linked to a scene (or zone) as `ambient`
- **Trigger types**: `on_enter` (scene/zone), `on_event` (variable change), `timed` (every N seconds), `one_shot` (plays once)
- **Display**: speech bubbles above the speaking pin, or subtitles at bottom of screen
- **Non-blocking**: player can move, click, interact while ambient flow runs
- **Auto-advance**: dialogue lines advance on a timer (configurable per node: 2s, 4s, etc.)
- **Interruption**: if the player triggers a full flow (from a pin/zone click), ambient flow pauses. Resumes after
- **Flow features**: conditions work normally — companion says different things based on variable state

### Schema changes
- New join schema: `SceneAmbientFlow`
  - `scene_id`, `flow_id`
  - `trigger_type`: `on_enter` | `on_event` | `timed` | `one_shot`
  - `trigger_config` (jsonb): `{"zone_id": "...", "delay_ms": 5000, "event_variable": "..."}`
  - `priority` (integer): when multiple ambient flows trigger, higher priority plays first
  - `position` (integer): ordering

### Design considerations
- Ambient flows reuse the existing PlayerEngine but with a different UI renderer (bubbles instead of overlay)
- Multiple ambient flows can queue or overlap — need a priority/queue system
- The speaking pin must be identified — ambient flows should reference which pin "speaks" (via speaker_sheet_id on dialogue nodes, matched to pins with the same sheet)
- Speech bubble positioning: above the pin, follows if NPC is patrolling
- Auto-advance timing: could be based on text length (words per minute) or manual per-node
- Ambient flows should NOT have entry/exit choices — they're linear narration. If a flow has branches, it becomes a full interactive flow
- Consider: ambient sounds (non-speech) as part of ambient flows — a node with only audio_asset_id plays a sound effect

### Acceptance criteria
- [ ] Scene settings: link ambient flows with trigger configuration
- [ ] `on_enter` trigger fires when entering the scene
- [ ] `on_event` trigger fires when a specific variable changes
- [ ] `timed` trigger fires periodically
- [ ] `one_shot` trigger fires once and marks as completed
- [ ] Dialogue appears as speech bubbles above the speaking pin
- [ ] Player can move and interact while ambient flow runs
- [ ] Ambient flow pauses when a full flow is active, resumes after
- [ ] Conditions in ambient flow nodes evaluate correctly
- [ ] Multiple ambient flows respect priority ordering

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
