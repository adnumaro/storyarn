# Epic 1 — Playable Exploration

> Foundation: make the scene feel like a game you can play

## Context

The current Exploration Mode renders the scene at image size, displays zones/pins, and allows clicking to trigger flows or instructions. It works but feels like an **interactive document**, not a game. This epic transforms it into something that feels **playable**.

Each feature below is independent and has standalone value. They are ordered by dependency (later features benefit from earlier ones) but each delivers value on its own.

---

## Feature 1: Display Modes + CRPG Camera

### What
Add a scene-level display mode setting for exploration:
- **fit** (default): scene scales to fit the viewport entirely (current behavior)
- **scaled**: scene renders at a size proportional to its scale configuration, potentially larger than the viewport

When the scene overflows the viewport (scaled mode with a large scene), enable CRPG-style edge-scroll camera: moving the mouse near screen edges pans the view in that direction (Baldur's Gate, Divinity style).

### Why (standalone value)
A scene that fills your screen and scrolls when you move to the edges **immediately** feels like a game map instead of a diagram. This single change transforms the atmosphere of exploration.

### Schema changes
- `Scene`: add `exploration_display_mode` field (string enum: `fit` | `scaled`, default: `fit`)

### Key implementation areas
- **Backend**: Scene schema + changeset + settings panel UI
- **Frontend** (`exploration_player.js`):
  - `fit` mode: current behavior (aspect-ratio container)
  - `scaled` mode: container sized proportionally to scale, positioned within a viewport wrapper
  - Edge-scroll system: detect mouse proximity to viewport edges, animate camera offset via CSS transform or scroll
  - Configurable: scroll speed, edge threshold (dead zone size), smooth acceleration/deceleration

### Design considerations
- Edge-scroll should feel smooth, not jerky — ease-in when entering edge zone, constant speed at full edge
- Need a "dead zone" in center where no scrolling happens (most of the screen)
- Touch/mobile: consider swipe-to-pan as alternative (or defer mobile to later)
- Keyboard arrows as alternative scroll method
- The scale_value/scale_unit already exist — the `scaled` mode uses them to calculate render size relative to viewport

### Acceptance criteria
- [ ] Scene settings panel shows display mode selector (fit/scaled)
- [ ] `fit` mode behaves exactly as current exploration
- [ ] `scaled` mode renders scene larger than viewport when appropriate
- [ ] Mouse at screen edges pans camera smoothly in that direction
- [ ] Camera stops at scene boundaries (no panning into void)
- [ ] Keyboard arrow keys also pan the camera
- [ ] Scene elements (pins, zones, annotations) position correctly in both modes

---

## Feature 2: Walkable Zones + Character Movement

### What
A new zone behavior: **walkable area**. In exploration mode, when the player clicks inside a walkable zone, the character pin moves to that point.

- Zones can be marked as `walkable` (new flag or zone type)
- Pins can be marked as `is_playable` (player-controlled character)
- One playable pin can be `is_leader` (the one that moves on click; others follow)
- Click inside walkable zone → leader pin animates in straight line to clicked point
- Click outside any walkable zone → nothing happens (or visual feedback: "can't go there")

### Why (standalone value)
This is THE core CRPG/Point & Click interaction. Clicking on the ground and watching your character walk there is the fundamental mechanic. Without this, it's a viewer. With this, it's a game.

### Schema changes
- `SceneZone`: add `is_walkable` field (boolean, default: false)
- `ScenePin`: add `is_playable` field (boolean, default: false)
- `ScenePin`: add `is_leader` field (boolean, default: false)

### Key implementation areas
- **Backend**: Schema changes, changeset validations, settings UI for zones and pins
- **Zone editor**: toggle to mark zone as walkable, distinct visual style in edit mode (e.g., green tint overlay)
- **Pin editor**: toggles for `is_playable` and `is_leader`
- **Exploration player** (`exploration_player.js`):
  - Point-in-polygon detection: click coordinates → check if inside any walkable zone
  - Movement animation: lerp pin position from current to target over time
  - Collision with walkable boundary: if straight-line path exits walkable area, stop at boundary (simple) or find path within polygon (complex — defer pathfinding to later)
  - Party following: non-leader playable pins follow the leader with slight delay/offset

### Design considerations
- **Movement speed**: configurable per scene or per pin? Start with scene-level constant, refine later
- **Visual feedback on click**: subtle click indicator (expanding circle) at target point
- **Non-walkable click**: brief red flash or "blocked" cursor to communicate "can't go there"
- **Multiple walkable zones**: they can overlap or be adjacent — character can move between connected walkable zones seamlessly
- **Adjacent walkable zones**: if two walkable zones share an edge/overlap, treat them as one continuous walkable area
- **Pathfinding**: V1 = straight line movement only. If the straight line exits the walkable polygon, stop at the boundary. Future: proper navmesh pathfinding within/across walkable zones
- **Party system**: leader moves directly, companions follow with slight delay and offset (fan formation or single file). Defer complex party AI to Epic 3

### Acceptance criteria
- [ ] Zone editor shows "Walkable" toggle
- [ ] Pin editor shows "Playable" and "Leader" toggles
- [ ] Walkable zones have distinct visual style in edit mode
- [ ] In exploration: clicking inside walkable zone moves leader pin to that point
- [ ] Movement is animated (not teleport)
- [ ] Clicking outside walkable zones does nothing (with visual feedback)
- [ ] If multiple pins are playable, non-leaders follow the leader
- [ ] Walkable zones are invisible in exploration (they define traversable area, not visual elements)
- [ ] Validation: at most one pin per scene can be `is_leader`

---

## Feature 3: Collection Zones

### What
Zones configured as collection points that, when clicked in exploration mode, open a modal showing available items (linked sheets). The player can collect individual items or take all.

Each item in the collection zone has:
- A sheet reference (the item itself — displays name, avatar, description from the sheet)
- A **condition** (visibility: is the item still there? e.g., `inventory.potion != true`)
- An **instruction** (what happens when collected: e.g., `inventory.potion = true`)

### Why (standalone value)
Searching a room, looting a chest, picking herbs — this is the second most fundamental interaction after movement. It lets designers create explorable environments with discoverable content.

### How it connects to existing systems
- The **variable system** (sheets/blocks) IS the inventory. A sheet called "Inventory" with boolean blocks = items the player has
- **Conditions** control whether an item appears (already collected? quest requirement met?)
- **Instructions** execute on collection (set variable, increment counter)
- Zone `action_type: instruction` already exists — this extends it with a **multi-item presentation layer**

### Schema changes
- `SceneZone`: new `action_type` value: `collection`
- `SceneZone`: `action_data` for collection type:
  ```json
  {
    "items": [
      {
        "id": "id",
        "sheet_id": "id",
        "label": "Health Potion",
        "condition": { "logic": "all", "rules": [...] },
        "instruction": { "assignments": [...] }
      }
    ],
    "collect_all_enabled": true,
    "empty_message": "Nothing here..."
  }
  ```

### Key implementation areas
- **Backend**: Zone schema validation for `collection` action_type, serialization
- **Zone editor**: UI to configure collection items — sheet picker, condition builder, instruction builder per item
- **Exploration player**:
  - Click on collection zone → `pushEvent("open_collection", %{zone_id: id})`
  - LiveView evaluates conditions per item, returns visible items
  - Modal component: grid/list of items with sheet avatar, name, description
  - "Take" button per item → executes instruction → re-evaluates visibility
  - "Take All" button → executes all instructions sequentially
  - When all items collected (or on close), dismiss modal

### Design considerations
- **Modal design**: should feel like opening a chest or searching a bookshelf, not like a data table. Card-based layout with item images
- **Empty state**: configurable message when all items are collected ("The chest is empty", "Nothing left to find")
- **Feedback on collect**: brief animation/sound, item fades or disappears from modal
- **Zone visual state**: optionally change zone appearance when empty (e.g., open chest sprite vs closed chest). Could be done via condition on the zone's visual properties
- **Future: unlock/attack mechanics** (Epic 3): the zone itself would have an access condition + alternative actions. The architecture should NOT hardcode "click → open modal" — it should support an interaction pipeline: check access → resolve interaction method → show result. For now, the pipeline has one step (open modal), but the data model should allow inserting steps later
- **Item order**: items display in the order defined by the designer (array index)

### Acceptance criteria
- [ ] New `collection` action_type available for zones
- [ ] Zone editor: add/remove/reorder items with sheet picker
- [ ] Zone editor: condition and instruction builder per item
- [ ] Zone editor: "Collect All" toggle and empty message configuration
- [ ] Exploration: clicking collection zone opens item modal
- [ ] Modal shows only items whose conditions are met
- [ ] "Take" executes item instruction and removes it from modal
- [ ] "Take All" executes all visible item instructions
- [ ] Empty state message shows when no items remain
- [ ] Variables update in real-time (other zones/pins react to collected items)

---

## Feature 4: Exploration Session Persistence

### What
Save and load exploration state across browser sessions. When a player leaves and returns, their progress (variables, character position, collected items, discovered areas) is preserved.

### Why (standalone value)
Without persistence, exploration resets every time you close the browser. This makes long or complex explorations pointless. Persistence transforms exploration from a "demo" into a "playthrough".

### Schema changes
- New schema: `ExplorationSession`
  - `id`, `user_id`, `scene_id`, `project_id`
  - `name` (optional, for multiple saves: "Autosave", "Before boss fight")
  - `started_at`, `updated_at`
  - `status`: `active` | `completed` | `abandoned`
- New schema: `ExplorationState`
  - `id`, `session_id`
  - `variable_snapshot` (jsonb): full variable state at save time
  - `player_position` (jsonb): `%{"scene_id" => id, "x" => float, "y" => float}`
  - `party_positions` (jsonb): `[%{"pin_id" => id, "x" => float, "y" => float}]`
  - `metadata` (jsonb): extensible field for future state (discovered zones, etc.)
  - `saved_at`

### Key implementation areas
- **Backend**: New schemas, migrations, context module (`Storyarn.Exploration` or extend `Storyarn.Scenes`)
- **Autosave**: periodic save (every N seconds or on significant action)
- **Manual save/load**: UI in exploration toolbar — save button, load button with session list
- **Session selection on enter**: if sessions exist for this scene+user, show "Continue" / "New exploration" / "Load save" options
- **Variable restore**: on load, override current variable state with snapshot
- **Position restore**: place character/party at saved positions
- **Multi-scene awareness**: if the player has navigated to child scenes, save which scene they're in

### Design considerations
- **Save slot model vs auto-only**: start with autosave + one manual save slot. Expand later if needed
- **Conflict with collaboration**: exploration state is per-user, not shared (unlike edit mode which is collaborative). Clear separation needed
- **Variable snapshot strategy**: save the full variable map as JSON, not individual deltas. Simpler, more reliable, easy to debug
- **Storage**: database (not localStorage) — accessible from any device, auditable
- **Cleanup**: auto-delete abandoned sessions after N days
- **Future consideration**: shared exploration sessions (multiplayer TTRPG) — one session with multiple users. Defer but keep schema flexible

### Acceptance criteria
- [ ] Exploration sessions are created on entering exploration mode
- [ ] Autosave triggers periodically and on significant actions
- [ ] Manual save creates a named checkpoint
- [ ] Entering exploration shows options: New / Continue / Load
- [ ] Loading a save restores variables, position, and party
- [ ] Sessions are per-user, per-scene
- [ ] Old abandoned sessions are cleaned up
- [ ] Session state survives browser close and reopen
