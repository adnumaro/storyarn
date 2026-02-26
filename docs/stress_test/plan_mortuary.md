# Stress Test Plan — Planescape: Torment — The Mortuary

**Date:** 2026-02-24
**Scope:** Complete Mortuary section (game opening through escape)
**Method:** Manual browser testing — all actions via Chrome UI clicks
**Goal:** Identify UX issues, bugs, and workflow friction during real narrative design work

**Structure:** Each phase is a *movie shot* — a self-contained vertical slice that combines **sheets** (characters/data), **scene** (location), and **flow** (dialogue/action). After each phase, the content can be played and verified independently.

**Feature principle:** Use EVERY available feature across the test. Each phase introduces new features naturally, not artificially.

**CRITICAL — Issue logging rule:** The primary goal of this stress test is to **find and document issues**. ANY problem encountered during execution — error flash messages, crashes, unresponsive UI, unexpected behavior, confusing UX, missing features, layout glitches, wrong data, slow performance, etc. — MUST be written **immediately** to `docs/stress_test/issues.md` the moment it is discovered. Do NOT continue with the next step until the issue is logged. Do NOT batch issues for later. Every issue gets its own numbered entry with severity, context, reproduction steps, and expected vs actual behavior. This is the entire point of the stress test.

**Agent instructions:** All browser actions go through Chrome MCP tools. Asset files live at `docs/game_references/planescape_torment/` relative to project root. Curated dialogue content for each flow is at `docs/game_references/planescape_torment/dialogs/curated/sigil/mortuary/`. Read the relevant JSON file BEFORE building each flow to get actual dialogue text. Upload images via the hidden `<input id="asset-upload-input">` file input element. Node creation in flows uses the "Add Node" dropdown in the flow header bar (select type → node appears on canvas → configure in right sidebar panel).

---

## Phase 0: Pre-Production — Project & Assets

**Objective:** Set up the project and upload all assets so they're ready when needed.

**Asset source directory:** `docs/game_references/planescape_torment/` (relative to project root)

### Steps
1. Open app at localhost:4000
2. Navigate to existing workspace
3. Create project "Planescape: Torment"
4. Switch between all tools (Flows, Sheets, Assets, Scenes) — verify empty states
5. Go to Assets tool and upload (via the file input `#asset-upload-input`):
   - **Character art:** `characters/PC-NamelessOne.jpg`, `companions/Deionarra.png`
   - **Bestiary art:** `bestiary/Zombie_male.png`, `bestiary/Skeleton102018.jpg`
   - **Maps:** `maps/Mortuary1st_floor_map.jpg`, `maps/Mortuary_2nd_floor_map.jpg`, `maps/Mortuary_3rd_floor_map.jpg`, `maps/Mortuary_area_map.jpg`
6. Test asset library: filter tabs (All/Images/Audio), search by filename, click card to see detail panel
7. Verify detail panel: preview, metadata, usage section (empty)

### Features tested
- Project creation, slug generation
- Sidebar tool switching, empty states
- Asset upload, library grid, filter tabs, search, detail panel

---

## Phase 1: The Awakening — TNO meets Morte

> *The Nameless One wakes on a stone slab in the Preparation Room. A floating skull introduces himself.*

### SHEETS

**Build the character hierarchy with inheritance:**

1. Create root sheet "Characters" (grouping container — no blocks of its own)
2. Create child "Main Characters" — this is the **template parent**
3. On "Main Characters", add blocks with **scope: children**:
   - **Divider:** "Attributes"
   - **Number:** Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma (all scope: children)
   - **Divider:** "Alignment"
   - **Number:** Law-Chaos (scope: children) — negative=chaos, positive=law
   - **Number:** Good-Evil (scope: children) — negative=evil, positive=good
   - **Divider:** "Class & Progression"
   - **Select:** Current Class — options: [Fighter, Mage, Thief] (scope: children)
   - **Number:** HP Max (scope: children)
   - **Number:** XP Total (scope: children)
   - **Divider:** "Notes"
   - **Rich Text:** Background (scope: children, is_constant: true)
   - **Reference:** Location — allowed_types: ["scene"] (scope: children)
4. Set **sheet color** on Main Characters
5. Set a **banner** color

**Create "The Nameless One" as child of Main Characters:**

1. Create as child — **verify all inherited blocks appear** with blue left border, "Inherited from Main Characters" header
2. **Override inherited values:**
   - Strength: 9, Dexterity: 9, Constitution: 9, Intelligence: 9, Wisdom: 9, Charisma: 9
   - Current Class: Fighter
   - HP Max: 26
   - Background: Write TNO lore (rich text with bold, italic, lists)
3. **Add own blocks** (scope: self):
   - **Select:** Appearance — [Normal, Zombie Disguise, Dustman Robes]
   - **Boolean:** Escaped Mortuary, Has Journal, Stories-Bones-Tell
   - **Multi-Select:** Known Languages — [Common, Planar Cant, Celestial, Infernal, Shou Lung]
   - **Date:** Last Death
4. Set **avatar** from PC-NamelessOne.jpg asset
5. Set **sheet color** (will tint flow nodes later)
6. Test **inline label editing** (double-click block labels)
7. **Set shortcut** to `tno` (click the # shortcut, edit to `tno`) — all variable references use this shortcut (e.g., `tno.strength`)
8. Group some blocks into **2-column layout**
9. Mark the Strength block as **required** (test required flag on inherited blocks)

**Create "Morte" as child of Main Characters:**

1. Create as child — verify inheritance
2. Override: STR 12, DEX 16, CON 16, INT 13, WIS 9, CHR 6, Class: Fighter, HP Max: 20
3. Background: Write Morte bio (rich text)
4. Own blocks: **Text:** Race — "Floating Skull" (is_constant: true), **Number:** Loyalty (default 50), **Boolean:** Secret Revealed
5. **Set shortcut** to `morte` (click the # shortcut)
6. Set distinct **sheet color**
7. Test **detach** on one inherited block, then **reattach** it

### SCENE

**Create Mortuary 2nd Floor:**

1. Create scene group "Mortuary"
2. Create child "Mortuary 2nd Floor"
3. Upload **background** from `Mortuary_2nd_floor_map.jpg` asset
4. Set **scene scale** (1 scene width = 50 meters)
5. Create **layer** "NPCs" (keep default layer for zones)
6. Draw zones:
   - **Preparation Room** — Rectangle tool, blue fill — where TNO wakes
   - **Corridors** — Freeform tool, grey fill — connects rooms
7. Place pins (switch to NPC layer):
   - "TNO Start" — type: **character**, linked to TNO sheet (verify avatar shows!), size: large
   - "Morte" — type: **character**, linked to Morte sheet, size: medium
8. Add **annotation** "GAME START" (large, red, near TNO pin)
9. Create **connection** between TNO pin ↔ Morte pin — label "Meets at wakeup"

### FLOW

**Create "Morte - First Meeting" (17-state opening dialogue):**

> **Read first:** `docs/game_references/planescape_torment/dialogs/curated/sigil/mortuary/morte_first_encounter.json` — contains all dialogue text, responses, and state transitions.

1. Create flow group "Mortuary"
2. Create flow "Morte - First Meeting"
3. Add nodes via the **"Add Node" dropdown** in the flow header (or **right-click canvas → context menu**):
   - **Entry** node (auto-created)
   - **Dialogue** nodes for key states: Morte's introduction, TNO questions, Morte's explanations
   - Speaker: Morte (linked sheet — node turns Morte's sheet color)
   - Rich text with bold/italic
   - Stage directions (e.g., "Morte floats closer")
   - Responses with text for each choice
   - State 14: alignment responses → **Instruction** node: Good-Evil += 1
   - **Exit** node: "Morte Joins Party"
4. Connect all nodes (drag from output socket to input socket)
5. Use **auto-layout** to arrange nodes neatly
6. Test **response creation** — especially adding the first response to a node
8. Set **technical IDs** on key nodes (auto-generate)
9. **Attach audio** to one dialogue node (via AudioPicker in sidebar) — verify 🔊 indicator appears on canvas
10. Test **node duplication** (Ctrl+D on a dialogue node) — verify offset copy appears
11. Verify **minimap** shows node layout in bottom-right corner

### VERIFY

1. **Story Player:** Click "Play" → walk through dialogue, choose responses, reach exit → verify outcome screen with stats (steps, choices, variables changed)
2. **Story Player Analysis mode:** Press P → verify invalid responses shown greyed-out with red badge
3. **Debug Mode:** Ctrl+Shift+D → step through nodes (F10), check Variables tab, step back (F9)
4. **Preview Mode:** Click "Preview" (if available) on a dialogue node → verify modal walkthrough
5. Sheet references: Morte sheet → References tab → verify flow references appear
6. Scene pin: click Morte pin → verify link to flow

### Features introduced
- Property inheritance (scope:children, override, detach/reattach, required flag)
- Block types: number, select, boolean, rich_text, text, multi_select, date, divider, reference
- Avatar, banner, sheet color, inline editing, column layout, shortcut editing
- Scene creation, background, rectangle/freeform zones, character pins, annotations, connections
- Flow: dialogue nodes, speaker colors, responses, instruction, auto-layout, node duplication, context menu, minimap
- Audio attachment on dialogue nodes (🔊 indicator)
- Story Player (player + analysis mode), Debug Mode basics, Preview Mode

---

## Phase 2: The First Puzzle — Key Zombie 782

> *TNO discovers Zombie #782 who has a key gripped in death. First environmental puzzle.*

### SHEETS

**Create "Items" sheet (root level) with table block:**

1. Add **Table** block "Mortuary Items" with columns testing **ALL 7 data types**:
   - "Name" — type: `text`
   - "Type" — type: `select` (options: [Weapon, Quest, Consumable, Key])
   - "Quantity" — type: `number`
   - "Found" — type: `boolean`
   - "Found Date" — type: `date`
   - "Location" — type: `reference` (→ scene)
   - "Tags" — type: `multi_select` (options: [Main Quest, Side Quest, Combat, Puzzle])
2. Add rows: Scalpel, Mortuary Key, Embalming Thread, Note from 1201, Zombie Charm
3. Test: add column, add row, edit cells, delete a row, undo (verify Issue #2 fix)

**Create "Game State" sheet (root level):**

1. **Set shortcut** to `game-state`
2. Add blocks:
   - **Select:** Current Area — [Mortuary 2F, Mortuary 1F, Mortuary 3F, Mortuary Exterior]
   - **Number:** Copper Commons (default 0)
   - **Boolean:** Mortuary Alert

### SCENE

**Update Mortuary 2nd Floor:**

1. Add pin "Zombie #782" — type: **event**, custom color (red), size: small
2. Add pin "Scalpel" — type: **location** on Items layer (create new "Items" layer)
3. Test **layer visibility toggle** — hide/show Items layer
4. Add annotation "KEY: Zombie has room key" near zombie pin

### FLOW

**Create "Key Zombie 782" (3 states — narrator dialogue):**

1. Create flow "Zombie #782 — Key" under Mortuary group
2. **Entry** → **Dialogue** (no speaker = narrator mode) describing the zombie → **Exit**
3. Keep it minimal — tests fast flow creation

### VERIFY

1. Play through the 3-node flow in Story Player
2. Table: edit cells, verify all column types work, undo row creation
3. Pin click → flow link works

### Features introduced
- Table block with ALL 7 column data types (text, number, boolean, select, multi_select, date, reference)
- Table CRUD (add/edit/delete rows and columns), undo/redo with tables
- Multiple layers in scene, layer visibility toggle
- Event pin type, location pin type
- Narrator dialogue (no speaker)
- Fast flow creation workflow

---

## Phase 3: The Embalmer — Ei-Vene's Quest

> *The near-sighted embalmer has a delivery task. Completing it grants +1 HP. Pushing too far triggers the alarm.*

### SHEETS

**Build the NPC template hierarchy:**

1. Create "NPCs" sheet as child of Characters (grouping container with template blocks)
2. On "NPCs", add blocks with **scope: children**:
   - **Text:** Title (scope: children)
   - **Select:** Disposition — [Friendly, Neutral, Hostile, Varies] (scope: children)
   - **Select:** Faction — [Dustmen, Xaositects, Mercykillers, Independent] (scope: children)
   - **Boolean:** Can Trade, Has Quest (scope: children)
   - **Reference:** Location — allowed_types: ["scene"] (scope: children)
   - **Rich Text:** Description (scope: children, is_constant: true)
3. Create "Mortuary NPCs" sub-folder under NPCs

**Create "Ei-Vene" (child of Mortuary NPCs → inherits from NPCs):**

1. **Set shortcut** to `ei-vene`
2. Verify **deep tree** (4 levels: Characters > NPCs > Mortuary NPCs > Ei-Vene) — blocks inherit from NPCs (scope:children cascades through Mortuary NPCs)
3. Override: Title = "Embalmer", Disposition = Neutral, Faction = Dustmen, Has Quest = true
4. Own blocks: **Boolean:** Delivery Done, **Boolean:** Alarm Triggered
5. Write description (rich text about the near-sighted embalmer)

### SCENE

**Update Mortuary 2nd Floor:**

1. Draw **Embalming Chamber** zone — **Freeform** tool (test irregular shape), yellow fill
2. Place "Ei-Vene" pin — type: **character**, linked to Ei-Vene sheet
3. Set **zone tooltip** on Embalming Chamber: "Ei-Vene's workshop — approach carefully"
4. Set **zone action:** action_type = "display", action_data shows text about the room
5. Set Ei-Vene pin **target** → link to Ei-Vene flow
6. Place a "Corridor" pin (type: **location**) between the two rooms. Create **connection** from TNO Start pin → Corridor pin → Ei-Vene pin (dashed line, labeled "To Embalming Room"). **Note: connections are between pins only, NOT zones.**

### FLOW

**Create "Ei-Vene — Embalmer" (quest flow with conditions & instructions):**

> **Read first:** `dialogs/curated/sigil/mortuary/ei_vene_embalmer.json` — 28 states, quest flow with reward.

1. Create under Mortuary group
2. Build:
   - **Entry** → **Dialogue** "You there! You're one of mine, aren't you?"
   - Speaker: (create/link to Ei-Vene sheet — no avatar so test without one)
   - **Condition** node: `ei-vene.delivery_done == false` (test condition builder)
   - True path: **Dialogue** quest offer + responses
   - **Instruction** node: Set `tno.hp_max` += 1 (reward)
   - **Instruction** node: Set `ei-vene.delivery_done` = true
   - Alternative path: **Condition** for alarm trigger
   - **Instruction** node: Set `game-state.mortuary_alert` = true
   - Two **Exit** nodes: "Quest Complete" and "Alarm Triggered" (different outcome colors)
3. Test **condition builder** — select sheet, variable, operator, value
4. Test **instruction builder** — set variable with different operators (set, add)
5. Set outcome **tags** and **colors** on exit nodes

### VERIFY

1. **Debug Mode** on Ei-Vene flow: step through, check **Variables tab** updates when instruction fires
2. Set a **breakpoint** on the alarm instruction node — verify auto-play pauses there
3. Check **History tab** — variable change timeline
4. NPC sheet inheritance: Ei-Vene should show inherited blocks from NPCs template with correct values

### Features introduced
- NPC template hierarchy (deep inheritance, 4 levels)
- Condition nodes with variable picker, operators
- Instruction nodes with set/add operators
- Zone actions (display type), zone tooltips
- Pin targets linking to flows
- Debug mode: breakpoints, variable tracking, history tab
- Exit node outcome tags and colors
- Dashed connections, connection labels

---

## Phase 4: The Ancient Scribe — Dhall's Interrogation

> *The most complex dialogue in the Mortuary. A central hub where TNO can ask about everything — identity, escape, companions, the Dustmen. Stat checks gate advanced information.*

### SHEETS

**Create "Dhall" (child of Mortuary NPCs):**

1. **Set shortcut** to `dhall`
2. Override: Title = "Ancient Scribe", Disposition = Friendly, Faction = Dustmen, Has Quest = true
3. Own blocks: **Boolean:** Met, **Number:** Journal Entries Given (0-4)
4. Write description (rich text about the ancient dying scribe)

### SCENE

**Update Mortuary 2nd Floor:**

1. Draw **Dhall's Study** zone — **Rectangle** tool, green fill
2. Place "Dhall" pin — type: **character**, linked to Dhall sheet
3. Set Dhall pin target → link to Dhall flow
4. Create **connections** between pins (Morte pin → Dhall pin, Zombie #782 pin → a new "Exit Stairs" location pin) — test various line styles (solid, dashed, dotted). **Note: connections are pin-to-pin only.**
5. Add **bidirectional** connection between TNO Start pin and Dhall pin
6. Test **connection waypoints** — double-click a connection line to add waypoint, drag it to create a bend, right-click to remove

### FLOW

**Create "Dhall — Ancient Scribe" (complex hub dialogue, 54 states):**

> **Read first:** `dialogs/curated/sigil/mortuary/dhall_scribe.json` — 54 states, 203 transitions, hub structure with stat checks.

1. Create under Mortuary group
2. Build the complex tree:
   - **Entry** → **Condition** "First meeting?" (`dhall.met == false`)
   - **Instruction**: Set `dhall.met` = true
   - **Dialogue** chain: recognition scene (speaker: no sheet = narrator, then Dhall responses)
   - **Hub** node "Questions Hub" — set hub ID, label, custom **color**
   - From hub, 5+ branch paths via dialogue chains:
     - "About the Mortuary" → chain → **Jump** back to hub
     - "How did I get here?" → chain → **Jump** back to hub
     - "Escape route" → chain → **Jump** back to hub
     - "Who am I?" → chain → **Jump** back to hub
     - "About your health" → separate exit
   - **Condition** nodes with stat checks:
     - INT > 12 — **compound condition** (ALL logic: INT > 12 AND WIS < 13)
     - WIS > 12 — single condition
   - **Instruction** nodes for alignment:
     - Helping: Good-Evil += 1
     - Dismissive: Good-Evil -= 1
   - **Multiple Exit** nodes with different outcome tags + colors:
     - "Blessing" (green, tag: Peaceful)
     - "Cursory Farewell" (neutral)
3. Create SEPARATE flow **"Vaxis Subplot"** (short side quest)
4. In Dhall flow, use **Subflow** node to reference Vaxis Subplot
5. Test **hub ↔ jump** bidirectional zoom navigation (click jump → zooms to hub and back)
6. Test **subflow** double-click → navigates to Vaxis flow
7. Test **compound conditions** (ALL/ANY logic toggle)

### VERIFY

1. **Debug Mode** — walk through ALL hub branches, verify variable changes in History
2. Test **LOD** — zoom out on the 20+ node canvas, verify simplified view kicks in
3. **Story Player** — full playthrough choosing different branches
4. Cross-flow navigation: subflow → Vaxis → back (breadcrumbs)
5. Hub shows jump count; jumps show hub label as nav link

### Features introduced
- Hub + Jump nodes (color inheritance, bidirectional zoom, jump count)
- Subflow node (cross-flow reference, double-click navigation)
- Compound conditions (ALL/ANY logic)
- Multiple exits with distinct tags and colors
- LOD (level of detail at zoom out)
- Cross-flow navigation breadcrumbs
- Connection waypoints, bidirectional connections, varied line styles

---

## Phase 5: The Ghost — Deionarra's Memorial

> *On the 1st floor, TNO finds Deionarra's ghost in the Memorial Hall. An emotional encounter with branching based on honesty vs deception.*

### SHEETS

**Create "Deionarra" (child of Mortuary NPCs):**

1. **Set shortcut** to `deionarra`
2. Override: Title = "Ghost", Disposition = Varies, Faction = None
3. Own blocks: **Select:** Relationship State — [Unknown, Hopeful, Furious], **Boolean:** Prophecy Revealed
4. Set **avatar** from `companions/Deionarra.png`
5. Write description (rich text about the ghostly figure)

### SCENE

**Create Mortuary 1st Floor (NEW scene):**

1. Create "Mortuary 1st Floor" as child of Mortuary group
2. Upload background from `Mortuary1st_floor_map.jpg`
3. Draw zones:
   - **Memorial Hall** — **Circle** tool (test circle zones!), purple fill, low opacity
   - **Storage Rooms** — Rectangle, grey
   - **Front Gate** — **Triangle** tool (test triangle!), red fill
4. Create layers: "Layout" (default), "NPCs", "Annotations"
5. Place pins:
   - "Deionarra" — type: **character**, linked to Deionarra sheet (avatar shows!), size: large
   - "Front Gate Guard" — type: **character** (no sheet link yet)
6. Set Deionarra pin **target** → link to Deionarra flow
7. Add **annotation** "BOSS DIALOGUE — emotional branching" near Deionarra
8. Test **locking** — lock the Deionarra pin, try to delete it (should fail)
9. Test **ruler tool** — measure distance between Deionarra and Front Gate

### FLOW

**Create "Deionarra — Ghost Encounter" (emotional branching):**

> **Read first:** `dialogs/curated/sigil/mortuary/deionarra_ghost.json` — 76 states, emotional branching.

1. Create under Mortuary group
2. Build:
   - **Condition**: `deionarra.relationship_state == "Unknown"` (select variable check)
   - **Dialogue** chain — emotional encounter (speaker: Deionarra, her sheet color tints nodes)
   - Branching:
     - Honest path → **Instruction**: Set `deionarra.relationship_state` = "Hopeful"
     - Deceptive path → **Instruction**: Set `deionarra.relationship_state` = "Furious", Good-Evil -= 1
   - **Condition** nodes: INT > 11, CHR > 10
   - **Multiple exits:** "Hopeful Farewell", "Furious Farewell", "Left Without Speaking"
3. Test **instruction** with select variable assignment

### VERIFY

1. Debug Mode: walk through both emotional paths
2. Cross-navigation: Deionarra sheet → References tab → flow link → flow (roundtrip)
3. Ruler measurements on 1st floor scene
4. Pin locking works (can't delete locked pin)

### Features introduced
- Circle and triangle zone shapes (all 4 shapes now used)
- Select variable conditions and assignments
- Multiple scenes in project
- Pin locking
- Ruler tool with scene scale
- Cross-domain navigation roundtrip (sheet → flow)

---

## Phase 6: The Escape — Past the Guards

> *TNO must get past the Dustman guards on the 1st floor, then through the front gate to the exterior. DEX checks for combat, CHR checks for bluffing.*

### SHEETS

**Create "Dustman Guard" (child of Mortuary NPCs):**

1. Override: Title = "Guard", Disposition = Hostile, Faction = Dustmen
2. No own blocks — tests minimal NPC using only inherited fields

**Create "Bestiary" sheet (root level):**

1. Add **Table** block "Creatures" with columns: Name (text), HP (number), Hostile (boolean), Location (reference → scene)
2. Rows: Zombie Worker, Dustman Guard, Cranium Rat
3. Link Location reference cells to Mortuary scenes

### SCENE

**Update Mortuary 1st Floor:**

1. Place "Dustman Guard 1" pin — type: **character**, linked to Dustman Guard sheet
2. Place "Dustman Guard 2" — **duplicate** pin (test Ctrl+Shift+D duplicate)
3. Set **zone condition** on Front Gate: condition = `game-state.mortuary_alert == true`, effect = "disable"
4. Set **zone action** on Front Gate: action_type = "instruction" — sets `tno.escaped_mortuary` = true
5. Enable **Fog of War** on a layer (test fog settings: color, opacity)
6. Test **search panel** — search for "Guard", verify filtering + dimming

**Create Mortuary Exterior (NEW scene):**

1. Create "Mortuary Exterior" as child of Mortuary group
2. Upload background from `Mortuary_area_map.jpg`
3. Draw zones: Entrance (rectangle), Mourner's Corner (freeform), Road to Hive (rectangle)
4. Place pins: Gate Guard (character), note about exit directions
5. Create scene connection concept: annotate "From 1st Floor" on entrance zone

### FLOW

**Create "Dustman Guard — Confrontation" (DEX check):**

> **Read first:** `dialogs/curated/sigil/mortuary/dustman_guard.json` — 21 states, DEX check.

1. **Entry** → **Dialogue** "Hold! No one leaves the Mortuary!"
2. **Condition**: DEX > 12 (test number comparison)
   - True → **Dialogue** "You snap the guard's neck" → **Instruction**: Alert = true → **Exit** "Combat Escape"
   - False → **Dialogue** "The guard blocks your path" → **Exit** "Blocked"

**Create "Gate Guard — Bluff" (CHR check):**

> **Read first:** `dialogs/curated/sigil/mortuary/dustman_gate_guard.json` — 8 states, CHR check.

1. **Entry** → **Condition**: `tno.appearance == "Dustman Robes"` (select check)
   - True → **Dialogue** "Carry on, brother" → **Exit** "Free Pass"
   - False → **Condition**: CHR > 14 → True: Bluff works → False: **Exit** "Denied"

### VERIFY

1. Debug both flows with different variable values (edit variables inline in Debug panel)
2. Fog of War: verify layer fog renders on scene canvas
3. Search panel: results filter and dim non-matching elements
4. Duplicate pin: verify " (copy)" suffix, no sheet link copied
5. Zone condition + action: verify behavior in exploration mode (Phase 8)

### Features introduced
- Zone conditions with hide/disable effects
- Zone actions (instruction type)
- Fog of War on layers
- Scene search panel with type filtering, dimming
- Pin duplication
- Minimal NPC sheets (testing inherited-only blocks)
- Table reference cells linking to scenes
- Two parallel short flows (tests workflow speed)

---

## Phase 7: The Background — Minor Encounters

> *Remaining NPCs and loose ends. A batch phase for completeness, also tests less-common features.*

### SHEETS

**Create remaining NPCs:**

1. "Widow Mourner" (child of Mortuary NPCs or separate) — Override: Title = "Mourner", Disposition = Neutral, Own: **Boolean:** Pissed Off
2. "Dustman Worker" (child of Mortuary NPCs) — Override: Title = "Worker", Disposition = Neutral

**Create "Factions" sheet (root level):**

1. **Text:** Name — "The Dustmen" (is_constant)
2. **Rich Text:** Philosophy (is_constant) — True Death beliefs
3. **Select:** TNO Relationship — [Unknown, Member, Enemy]
4. **Boolean:** Joined
5. **Reference:** HQ Location — link to Mortuary scene

**Test remaining sheet features:**

1. **Versioning** — go to TNO sheet, History tab, create version "After Mortuary Setup"
2. **Hide for children** — on NPCs template, hide one block from cascading to children
3. **Sheet Audio tab** — go to Morte sheet, Audio tab (should list all dialogue nodes where Morte speaks)
4. **Column layout** — put some blocks in 3-column layout on a sheet

### SCENE

**Populate remaining scenes:**

1. Mortuary 2F: add "Exit Stairs Down" zone (circle, red) and "Exit Stairs Up" zone (triangle, orange)
2. Mortuary 1F: add Zombie #1201 pin (event), Zombie #1041 pin (event)
3. Mortuary Exterior: add Widow Mourner pin (character, linked to sheet)
4. **Create Mortuary 3rd Floor** — upload map, add minimal "Ritual Chamber" zone, "Upper Corridors" zone

**Test scene features:**

5. **Zone → child scene drill-down** — double-click a named zone to create child scene (auto-crop background)
6. **Legend** — verify auto-generated legend with pin types + zone colors
7. **Export** — test PNG export and SVG export
8. **Copy/paste** — copy a pin (Ctrl+Shift+C), paste (Ctrl+Shift+V)
9. **Context menu** — right-click on canvas (Add Pin Here), right-click on element (properties, delete, etc.)
10. **Keyboard shortcuts** — Shift+R/T/C/F/P/N/L/M to switch tools
11. **Custom pin icon** — upload a custom icon image on one pin (via "change icon" in floating toolbar) — tests `icon_asset_id`

### FLOW

**Create batch flows (short):**

1. **"Widow Mourner"** (read `widow_mourner.json`) — 6 dialogue nodes, pure comedy, no speaker (narrator). Test fast creation.
2. **"Zombie #1201 — Note"** (read `zombie_1201_note.json`) — 3 nodes: environmental puzzle, requires scalpel (condition)
3. **"Zombie #1041 — Bei"** (read `zombie_1041_bei.json`) — Longer flow with condition (`tno.stories_bones_tell == true`)
4. **"Dustman Background"** (read `dustman_background_npcs.json`) — 2 dialogue nodes, generic responses

**Test flow features:**

5. **Main flow** — designate one flow as "main" (shows badge)
6. **Flow tree reordering** — drag flows in sidebar tree to reorder
7. **Trash & restore** — delete a flow, go to trash, restore it
8. **Stale reference detection** — rename a variable on a sheet, check for warning icon on condition nodes that reference it

### VERIFY

1. All scenes have pins linked to sheets and flows
2. Sheet References tab shows all incoming references from flows and scenes
3. Sheet Audio tab shows voice lines grouped by flow
4. Version created, visible in History tab
5. Trash restore works — flow returns to tree
6. Stale references appear with warning icon

### Features introduced
- Sheet versioning (create, list)
- Sheet Audio tab (speaker-grouped voice lines)
- Hide for children (stop block cascade)
- 3-column layout
- Zone → child scene drill-down (auto-crop, create child)
- Scene legend, PNG/SVG export
- Scene copy/paste, context menu
- Custom pin icons (icon_asset_id upload)
- Main flow badge
- Flow tree reordering
- Trash & restore
- Stale reference detection
- Batch flow creation (workflow speed test)

---

## Phase 8: Post-Production — Localization & Exploration

> *Translation and interactive testing of everything built so far.*

### 8a. Localization — Full Pipeline

1. Go to Localization tool
2. Verify **source language** auto-created (English)
3. **Add target language** — Spanish (es)
4. Wait for extraction → verify texts populated
5. Browse translation table: filter by status "pending", filter by source type "flow_node", search "chief"
6. **Edit a translation** manually — change status through workflow: pending → draft → in_progress → review → final
7. **Add glossary entries:**
   - "Dustmen" → do not translate
   - "The Hive" → "La Colmena"
8. Check **Reports page:** progress by language, word counts by speaker, VO progress, content breakdown
9. **Export** translations as Excel (.xlsx) and CSV
10. Modify a dialogue node → re-check extraction → verify **auto-downgrade** (final → review when source changes)

### 8b. Exploration Mode — Interactive Playthrough

1. Open Mortuary 2nd Floor scene
2. Click "Explore" → fullscreen exploration mode
3. Click Morte pin → should launch "Morte - First Meeting" flow overlay
4. Walk through dialogue inside dimmed scene
5. Test **Escape** to exit flow overlay
6. Click zones with actions → verify instruction execution
7. Navigate between scenes if connected
8. Test **condition evaluation** — zones with conditions should hide/disable based on variable state

### VERIFY

1. Localization: extraction captured all dialogue, translation workflow functions, export downloads
2. Exploration mode: flows play on dimmed scene, variables update, conditions work

### Features introduced
- Localization: extraction, translation table, glossary, reports, export
- Translation workflow (pending → final) + auto-downgrade
- Exploration mode: interactive scene + flow overlay
- Cross-scene flow execution

---

## Phase 9: Final Verification — Cross-Cutting

> *Verify everything works together as a cohesive system.*

### Steps

1. **Variable references completeness:** Open condition builder in any flow → browse ALL project variables (TNO stats, Morte loyalty, Game State flags, NPC booleans, table variables)
2. **Sheet References tab:** TNO sheet → References → verify all flows referencing TNO variables listed
3. **Sheet Audio tab:** Morte sheet → Audio → verify all dialogue nodes with Morte as speaker
4. **Backlinks:** Check a scene → verify `get_elements_for_target` shows all pins/zones linking to it
5. **Cross-navigation roundtrip:**
   - TNO sheet → Reference block → scene
   - Scene → Morte pin → flow
   - Flow → speaker click → Morte sheet
   - Full circle!
6. **Collaboration test:** Open Dhall flow in two browser tabs → verify presence indicators, cursor sharing, node locking
7. **Undo/redo comprehensive:** Test in flow (node move, delete+restore, connection), scene (delete+undo), sheets (block changes)
8. **Performance:** Zoom out in Dhall flow (20+ nodes) → LOD kicks in, then zoom back in
9. **Project settings:** Settings → Team, Maintenance (repair variable references), verify
10. **Keyboard shortcuts round:** Flow shortcuts (Ctrl+Z, Delete, Ctrl+D, Escape), Scene shortcuts (Shift+R/T/C/F/P/N/L/M), Debug (F10, F9, F5)

### Features verified
- Variable picker across all sheets
- References tab, Audio tab, backlinks
- Cross-domain navigation (sheets ↔ flows ↔ scenes)
- Collaboration (presence, cursors, locks)
- Undo/redo across all editors
- LOD performance
- Project settings + maintenance
- All keyboard shortcuts

---

## Issue Tracking

**File:** `docs/stress_test/issues.md`
**Issue numbering:** Continue from Issue #8 (previous session ended at #7).

**RULE: Log immediately, not later.** The instant any issue is discovered — a flash error, a crash, a button that doesn't respond, confusing UX, wrong data, a visual glitch, slow performance, anything unexpected — STOP what you are doing and write it to `issues.md` before continuing. This is non-negotiable. The stress test exists to find these issues.

**What counts as an issue:**
- Error flash messages (red toasts)
- Server crashes / LiveView disconnects
- Buttons or UI elements that don't respond to clicks
- Features that behave differently than expected
- Confusing or misleading UX (user would be confused)
- Layout or visual glitches
- Slow performance or lag
- Data not saving or displaying incorrectly
- Missing validation or confusing error messages
- Any friction that would frustrate a real user

**Severity scale:**
- **Major** — crash, data loss, or feature completely broken
- **Moderate** — feature works but with significant UX friction
- **Minor** — cosmetic or minor UX improvement

**Entry format** (match existing entries in `issues.md`):
```markdown
## Issue #N: Short descriptive title

- **Severity:** major/moderate/minor
- **Status:** Open
- **Phase:** Phase X — name
- **Context:** What was being done when the issue occurred
- **Problem:** What happened (actual behavior)
- **Expected:** What should have happened
- **Reproduction:** Step-by-step to reproduce
- **Screenshot:** (if taken)
```

---

## Feature Coverage Matrix

| Feature                       | Phase   | Context                                                      |
|-------------------------------|---------|--------------------------------------------------------------|
| **Block types**               |         |                                                              |
| text                          | 1       | Morte race (constant)                                        |
| rich_text                     | 1       | Background lore                                              |
| number                        | 1       | Stats, HP, XP                                                |
| select                        | 1, 3    | Class, disposition, faction                                  |
| multi_select                  | 1       | Known languages                                              |
| boolean                       | 1, 3    | Flags, abilities                                             |
| date                          | 1, 2    | Last Death, table column                                     |
| divider                       | 1       | Section separators                                           |
| reference                     | 1, 7    | Location, HQ                                                 |
| table                         | 2, 6    | Items (all 7 types), Bestiary                                |
| **Table column types**        | 2       | text, number, boolean, select, multi_select, date, reference |
| **Inheritance**               | 1, 3    | scope:children, override, detach, reattach, hide, required   |
| **Avatar/Banner/Color**       | 1, 5    | Portraits, speaker tinting                                   |
| **Column layout**             | 1, 7    | 2-column, 3-column                                           |
| **Versioning**                | 7       | Create version, history tab                                  |
| **Zone shapes**               |         |                                                              |
| rectangle                     | 1       | Preparation Room                                             |
| freeform                      | 1, 3    | Corridors, Embalming Chamber                                 |
| circle                        | 5       | Memorial Hall                                                |
| triangle                      | 5, 7    | Front Gate, stairs                                           |
| **Pin types**                 |         |                                                              |
| character                     | 1       | TNO, Morte, NPCs                                             |
| event                         | 2       | Zombie #782                                                  |
| location                      | 2       | Scalpel                                                      |
| custom + custom icon          | 7       | Custom pin icon upload (icon_asset_id)                       |
| **Scene features**            |         |                                                              |
| Actions (instruction/display) | 3, 6    | Zone/pin actions                                             |
| Conditions (hide/disable)     | 6       | Gate zone condition                                          |
| Fog of War                    | 6       | Guard patrol layer                                           |
| Zone → child scene            | 7       | Drill-down                                                   |
| Ruler                         | 5       | Distance measurement                                         |
| Legend                        | 7       | Auto-generated                                               |
| Export (PNG/SVG)              | 7       | Download                                                     |
| Copy/paste/duplicate          | 6, 7    | Pins                                                         |
| Locking                       | 5       | Pin lock                                                     |
| Search panel                  | 6       | Filter + dim                                                 |
| **Flow node types**           |         |                                                              |
| Entry                         | 1       | Every flow                                                   |
| Exit                          | 1       | Every flow                                                   |
| Dialogue                      | 1       | Every flow                                                   |
| Condition                     | 3, 4    | Stat checks, variable checks                                 |
| Instruction                   | 1, 3    | Variable assignments                                         |
| Hub                           | 4       | Dhall questions hub                                          |
| Jump                          | 4       | Return to hub                                                |
| Subflow                       | 4       | Vaxis subplot                                                |
| **Audio on dialogue**         | 1       | AudioPicker, 🔊 indicator                                    |
| **Node duplication**          | 1       | Ctrl+D in flow canvas                                        |
| **Flow context menu**         | 1       | Right-click canvas for node creation                         |
| **Flow minimap**              | 1       | Bottom-right minimap                                         |
| **Preview Mode**              | 1       | Modal walkthrough preview                                    |
| **Required flag**             | 1       | Inherited block marked required                              |
| **Debug mode**                | 1, 3, 4 | Step, breakpoints, variables, history, path                  |
| **Story Player**              | 1, 4    | Full playthrough, analysis mode (P key)                      |
| **Localization**              | 8       | Extraction, translation, glossary, export                    |
| **Exploration mode**          | 8       | Interactive scene + flow overlay                             |
| **Collaboration**             | 9       | Presence, cursors, locks                                     |

## Data Summary

| Entity             | Count                                                                    |
|--------------------|--------------------------------------------------------------------------|
| Sheets             | ~12 (TNO, Morte, 5 NPCs, Items, Game State, Bestiary, Factions + groups) |
| Blocks             | ~80+ (inherited + own, all 10 types)                                     |
| Table columns      | ~15+ (all 7 data types)                                                  |
| Scenes             | 5+ (4 floors/areas + child from drill-down)                              |
| Zones              | ~15-20 (all 4 shapes)                                                    |
| Pins               | ~15-20 (all types)                                                       |
| Flows              | ~12 (Morte, Zombie, Ei-Vene, Dhall, Deionarra, Guards, Mourner, misc)    |
| Nodes              | ~80-100 (8 types: entry, exit, dialogue, condition, instruction, hub, jump, subflow) |
