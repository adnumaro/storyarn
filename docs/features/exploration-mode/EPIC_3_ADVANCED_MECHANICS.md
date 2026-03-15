# Epic 3 — Advanced Mechanics

> Deep game mechanics for complex prototypes

## Context

After Epics 1 and 2, the exploration mode has movement, items, living NPCs, ambient narrative, spatial audio, and discovery. This epic adds the **mechanical depth** needed for complex game prototypes: multi-step interactions, templates for rapid design, navigation aids, and workflow improvements.

Each feature is independent and delivers standalone value.

---

## Feature 1: Zone Interaction Chains (Unlock/Attack)

### What
Multi-step interaction pipelines for zones. Instead of "click → immediate result", zones can require **preconditions and alternative actions** before yielding their content.

Examples:
- **Locked chest**: requires key item → pick lock (skill check) → force open (strength check) → loot contents
- **Sealed door**: requires magic word (variable) → use battering ram (item) → find secret switch (discovery)
- **Guarded NPC**: defeat guard first (combat flow) → bribe (gold check) → sneak past (stealth check)

### Why (standalone value)
This is where prototyping starts to feel like actual game design. Multi-step interactions create puzzles, resource management decisions, and emergent gameplay. A designer can prototype a dungeon room with locked chests, trapped doors, and hidden passages — all without code.

### Key concepts
- **Interaction pipeline**: ordered list of interaction methods for a zone
- **Each method has**:
  - `condition` — can the player attempt this? (has lockpick? strength > 15?)
  - `label` — displayed to player ("Pick lock", "Force open", "Use key")
  - `icon` — visual indicator of method type
  - `action` — what happens on success (instruction + optional flow)
  - `failure_action` — what happens on failure (optional: break lockpick, trigger alarm)
  - `success_condition` — for skill checks: condition that determines pass/fail
- **Interaction modal**: shows available methods (only those whose conditions are met), player chooses one
- **After successful interaction**: zone opens to its inner content (collection items, flow, etc.)

### Schema changes
- `SceneZone`: extend `action_data` for a new interaction model:
  ```json
  {
    "interaction_methods": [
      {
        "id": "id",
        "label": "Pick lock",
        "icon": "lock-keyhole",
        "condition": { "logic": "all", "rules": [...] },
        "success_check": { "logic": "all", "rules": [...] },
        "success_instruction": { "assignments": [...] },
        "failure_instruction": { "assignments": [...] },
        "success_flow_id": null,
        "failure_flow_id": null
      }
    ],
    "inner_action_type": "collection",
    "inner_action_data": { "items": [...] }
  }
  ```

### Design considerations
- Interaction methods are shown as action buttons in a modal (not a dropdown)
- Only methods whose conditions are met are visible — hidden alternatives create mystery
- The "inner action" is what you get after succeeding — could be collection, flow, instruction, or nothing (the success IS the reward, like opening a door)
- Skill checks: evaluate `success_condition` against current variables. If true → success. If false → failure. This is deterministic (no dice rolling... unless we add a random variable later)
- Visual state: zone can show different states (locked, unlocked, broken). Implementable via condition-based zone styling
- Backward compatible: zones without `interaction_methods` work exactly as before (direct click → action)

### Acceptance criteria
- [ ] Zone editor: configure interaction methods with conditions, labels, icons
- [ ] Zone editor: define inner action (what happens after successful interaction)
- [ ] Exploration: clicking zone with interaction methods shows method selection modal
- [ ] Only methods whose conditions are met are shown
- [ ] Success/failure paths execute their respective instructions and flows
- [ ] After successful interaction, inner action becomes accessible
- [ ] Zones without interaction methods work as before (backward compatible)

---

## Feature 2: Zone Templates

### What
Pre-configured zone presets that create a fully configured zone with one click. Templates encode common game patterns so designers don't have to configure every field manually.

### Why (standalone value)
Configuration fatigue is the biggest threat to adoption. A designer who has to manually set up conditions, instructions, and items for every chest in a dungeon will give up. Templates reduce a 10-minute configuration to 2 clicks.

### Key concepts
- **Built-in templates**:
  - **Loot container**: collection zone with "Take" / "Take All". Configurable: items
  - **Shop/merchant**: collection-like zone but items require gold (instruction: `gold -= price`). Two-way: buy and sell
  - **NPC dialogue**: zone that launches a flow on click. Pre-configured with talk icon and cursor
  - **Locked container**: interaction chain (key/lockpick/force) → collection
  - **Teleport/exit**: zone that navigates to another scene
  - **Info point**: display zone showing a variable value (sign, notice board)
- **Template application**: select template → fill in specifics (which items? which flow? which scene?) → done
- **Custom templates** (future): save your own zone configuration as a reusable template

### Schema changes
- None for applying templates — they pre-fill existing fields
- Future (custom templates): `SceneZoneTemplate` schema with project-level storage

### Design considerations
- Templates live in the zone creation flow: "Add zone → Choose template or blank"
- Template applies defaults that the designer can then customize
- Templates should be discoverable and self-explanatory (icon + name + one-line description)
- Built-in templates cover 80% of use cases — custom templates are a power-user feature for later
- Templates are NOT a runtime concept — they're a design-time accelerator

### Acceptance criteria
- [ ] Zone creation offers template selection
- [ ] Each built-in template creates a properly configured zone
- [ ] All template fields are editable after application
- [ ] Templates are clearly labeled with icon and description
- [ ] "Blank zone" option remains for custom configuration

---

## Feature 3: Minimap

### What
A small overlay map in the corner of the exploration viewport showing the player's position, discovered areas, and key landmarks. Essential for large scenes using scaled display mode with CRPG camera.

### Why (standalone value)
When the scene is larger than the viewport (scaled mode), players lose spatial orientation. A minimap provides constant awareness of position within the larger scene — standard in every CRPG.

### Key concepts
- **Thumbnail**: downscaled version of the scene background image
- **Player indicator**: dot/icon at current position
- **Party indicators**: smaller dots for companions
- **NPC indicators**: optional dots for visible NPCs
- **Fog overlay**: discovered vs undiscovered areas (if fog of war is enabled)
- **Viewport frame**: rectangle showing what's currently visible on screen
- **Click to pan**: clicking on minimap moves camera to that position
- **Toggle**: can be hidden/shown by the player

### Schema changes
- `Scene`: add `show_minimap` (boolean, default: true) — designer can disable per scene

### Design considerations
- Minimap should be subtle — semi-transparent, small (15-20% of viewport width)
- Position: bottom-right or top-right corner (configurable?)
- Performance: minimap is a static thumbnail, not a re-render. Only indicators update
- Pin indicators on minimap use the pin's color for easy identification
- Minimap border could match scene theme/mood (ornate for fantasy, clean for sci-fi) — defer to later
- Mobile: minimap might be too small. Consider a full-screen map toggle instead

### Acceptance criteria
- [ ] Minimap renders in exploration mode (scaled scenes)
- [ ] Player position shown as indicator on minimap
- [ ] Viewport frame shows currently visible area
- [ ] Clicking minimap pans camera to that position
- [ ] Minimap can be toggled visible/hidden
- [ ] NPC and companion indicators shown
- [ ] Fog of war reflected on minimap (if enabled)
- [ ] Scene setting to enable/disable minimap

---

## Feature 4: Scene Transitions with Animations

### What
Smooth visual transitions when navigating between scenes (via zone targets, pin targets, or scene connections). Instead of an instant page load, the player sees a fade, slide, or custom transition.

### Why (standalone value)
Instant scene changes break immersion. A brief fade-to-black between rooms, a slide transition between connected areas — these small details make the exploration feel **cinematic** rather than like clicking links in a wiki.

### Key concepts
- **Transition types**: `fade` (fade to black and back), `slide` (directional slide based on exit direction), `cut` (instant, current behavior), `dissolve` (crossfade between scenes)
- **Configurable per connection**: a zone targeting scene B can specify its transition type
- **Duration**: configurable (default: 500ms)
- **Loading text**: optional text during transition ("Entering the Dark Forest...", "Meanwhile, in the tavern...")
- **Direction inference**: if the exit zone is on the right edge of the scene, slide left. If on bottom, slide up

### Schema changes
- `SceneZone`: add `transition_type` (string enum: `cut` | `fade` | `slide` | `dissolve`, default: `fade`)
- `SceneZone`: add `transition_duration_ms` (integer, default: 500)
- `SceneZone`: add `transition_text` (string, nullable, max 200 chars)

### Design considerations
- Transition happens client-side during the LiveView navigation/patch
- Preload the target scene background during transition to avoid flash of unstyled content
- Save exploration state before transition (position, variables)
- If target scene is not yet loaded, transition covers the loading time gracefully
- Transition text uses a readable font, centered, on black/dark background
- Consider: transition sound effect (whoosh, door creak) via audio asset — defer to later

### Acceptance criteria
- [ ] Zone editor: transition type, duration, and text settings
- [ ] `fade` transition: screen fades to black, loads scene, fades in
- [ ] `slide` transition: current scene slides out, new scene slides in
- [ ] `dissolve` transition: crossfade between scenes
- [ ] `cut` transition: instant (backward compatible, current behavior)
- [ ] Loading text displayed during transition when configured
- [ ] Transition covers any loading time gracefully
- [ ] Player position in new scene set correctly after transition

---

## Feature 5: Quick Preview from Editor

### What
A "Preview" button in the scene editor that launches exploration mode in-context (overlay or split view), allowing rapid iteration without full navigation. Edit → Preview → Edit → Preview in seconds.

### Why (standalone value)
The current workflow is: edit scene → navigate to exploration URL → test → navigate back → edit → repeat. This friction slows down iteration dramatically. Quick preview removes the navigation overhead, making the design-test loop **instant**.

### Key concepts
- **Preview overlay**: full-screen exploration mode rendered as an overlay on top of the editor
- **Quick toggle**: keyboard shortcut (e.g., `Ctrl+P` or `F5`) to enter/exit preview
- **State sync**: preview uses the current editor state (unsaved changes included)
- **Exit preserves position**: exiting preview returns to exactly where you were in the editor
- **Partial preview**: optionally preview from a specific pin position (right-click pin → "Preview from here")

### Schema changes
- None — this is a UI/workflow feature

### Design considerations
- Preview must use the same exploration player code — no separate implementation
- Preview state is ephemeral (not saved to ExplorationSession)
- Editor state is frozen during preview (no edits while previewing)
- Consider: showing a semi-transparent editor overlay during preview for reference
- Consider: "hot reload" — if the designer makes a change and re-enters preview, the change is immediately reflected
- Keyboard shortcut should not conflict with existing editor shortcuts
- Preview inherits the scene's display mode settings

### Acceptance criteria
- [ ] "Preview" button in scene editor toolbar
- [ ] Keyboard shortcut to toggle preview mode
- [ ] Preview launches exploration as overlay (no navigation)
- [ ] Current editor state (including unsaved changes) is used
- [ ] Exiting preview returns to editor at same position
- [ ] "Preview from here" on right-click context menu for pins
- [ ] Preview state is ephemeral (no session created)
- [ ] All exploration features work in preview mode
