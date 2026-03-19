# Storyarn Vision — Platform Expansion

> Storyarn is the source of truth for game design. It doesn't replace every tool — it connects them. What it owns, it owns completely. What it doesn't, it integrates deeply.

## Platform Identity

```
Storyarn (source of truth)
|
|- OWNS: Narrative, variables, scenes, prototyping,
|        localization, assets, GDD, exploration mode
|
|- INTEGRATES: Jira, Linear, Trello, Asana
|   -> Bidirectional task creation and status sync
|   -> Deep links back to Storyarn entities
|
|- EXPOSES: Public wikis (fandom-style)
|   -> Subdomain: wiki.mygame.storyarn.com
|   -> Community-facing lore, maps, characters
|   -> Ad-supported on free tier
|
|- EXPORTS: Unity, Unreal, Godot
|   -> Designed data used in production builds
```

---

## I. Game Engine Evaluation

### A. 3D Engine — Deferred

Building a 3D engine inside Storyarn is not the goal. The complexity breakdown:

| Component | Difficulty | AI Dependency |
|---|---|---|
| Image -> 3D pipeline (Tripo/Meshy API) | Medium | External API |
| 3D viewer (Three.js/Babylon) | Medium-High | 0% — pure engineering |
| Player controls | Medium | 0% |
| Scene composition | Very High | ~50% automatable |
| Collisions/navmesh | High | Partially automatable |
| Flow/dialogue integration | Medium | Already exists |

**Verdict:** Not viable as a short-term goal. If pursued later, the approach would be:
1. Integrate with external tools (Spine for 2D animation, Tripo/Meshy for 3D generation)
2. Use the Rust runtime (see section IV) to handle logic
3. Engine plugins handle rendering — Storyarn handles data

### B. 2D Engine in Exploration Mode — Viable

Storyarn already has ~70% of the foundation:
- Scene canvas with zones, pins, layers, background images
- Exploration mode with navigation
- Connections defining transitions between zones/pins
- Flow system for dialogues and logic
- Condition/instruction builders for variables and state
- Asset management with uploaded images

**What's missing for a playable 2D prototype:**

| Component | Difficulty | Notes |
|---|---|---|
| Player sprite + movement | Low-Medium | Point & click or WASD |
| Zone collision (is_solid flag) | Low | New field on zone schema |
| Trigger system (zone/pin -> flow) | Low | trigger_flow_id on zones/pins |
| Dialogue overlay during play | Medium | Flow player as overlay |
| Scene transitions | Low | Connections already define these |
| Character animation integration | Medium | Spine runtime (see below) |

**Target quality: Modern adventure games** (Return to Monkey Island, Broken Age).

For high-quality character animation, the approach is **integration, not building**:
- Artists work in **Spine** (industry standard, $70-300 license)
- Export `.json` + `.atlas` + `.png`
- Upload to Storyarn as asset
- Spine JS runtime renders in exploration mode
- Storyarn provides: placement, scale, animation state triggers

**This eliminates the need to build:**
- Spritesheet slicer
- Animation timeline editor
- Rigging editor
- Bone system
- State machine editor

**Storyarn UI needed:**

| Menu | Purpose | Complexity |
|---|---|---|
| Character config | Upload Spine export, set scale/speed | Low |
| Scene placement | Drag character to scene (like pins) | Low |
| Animation mapping | Link states to flow triggers | Medium |
| Walkable area | Paint walkable zones (zones already exist) | Medium |
| Interaction hotspots | Already pins/zones with triggers | Already exists |

---

## II. Configurable Game Mechanics

### The Vision

Users describe game mechanics in natural language. AI configures pre-built systems to match.

### The Approach: AI as Configurator, Not Code Generator

AI does NOT generate arbitrary code. AI configures **pre-built systems** from a catalog.

```
User: "Inventory with 20 slots, max carry weight 50kg"

AI generates configuration:
  { system: "inventory",
    slots: 20,
    weight_limit: 50,
    weight_variable: "player.carry_weight",
    ui_position: "bottom-right" }

AI does NOT generate:
  500 lines of custom JS
```

**Why this wins:**
- Consistent, tested output
- Exportable to Unity/Godot (plugins implement the same systems)
- Users can tweak parameters after generation
- AI accuracy 90%+ because decision space is finite
- Composable — combine inventory + crafting + trading

### Systems Catalog

```
Core Mechanics:
|- inventory         # slots, weight, categories, stacking
|- dialogue          # (already exists — flows)
|- quest_journal     # objectives, tracking, states
|- save_system       # save/load variable state

World Mechanics:
|- day_night_cycle   # time progression, hourly events
|- weather           # states, visual effects
|- minimap           # visited zones, fog of war
|- fast_travel       # discovered waypoints

Combat Mechanics:
|- turn_based        # turns, actions, stats
|- real_time_simple  # cooldowns, basic hitboxes
|- health_system     # HP, damage, death, respawn

Social Mechanics:
|- reputation        # factions, tiers
|- shop              # buy/sell, dynamic pricing
|- crafting          # recipes, materials, results
```

Each system has:
- Configuration schema (JSON Schema)
- Web implementation (preview in exploration mode)
- Export specification (for engine plugins to implement)

### What AI Can Do Well Today

| Mechanic Type | AI Viability | Why |
|---|---|---|
| Static UI (inventory, HUD, minimap) | High | HTML/CSS/JS, LLMs excel here |
| Variable logic (weight, stats, cooldowns) | High | Variable system already exists, AI just configures |
| Simple state machines (door open/closed) | High | Condition + instruction, already exists |
| Modified movement (speed, jump) | Medium-High | Numeric parameters, well-defined |
| Dialogue systems with branches | Already exists | Flow editor |

### What AI Does Poorly Today

| Mechanic Type | AI Viability | Why |
|---|---|---|
| Complex combat systems | Low | Too many emergent interactions, balance issues |
| Custom physics | Low | Subtle bugs, AI can't test the "feel" |
| NPC AI (pathfinding, behavior) | Medium-Low | Works in demo, breaks on edge cases |
| Netcode/multiplayer | Very Low | Don't attempt |

### Complexity Assessment

| Piece | Difficulty | Timeline |
|---|---|---|
| 3-5 base systems (inventory, quests, save, shop, health) | Medium-High | First milestone |
| AI configurator from natural language | Medium | Builds on existing variable system |
| 10-15 systems covering 80% of narrative/adventure/RPG games | High | Medium-term |
| AI composing multiple systems + connecting variables | High | Medium-term |
| UI editor for tweaking AI-generated config | Medium | After AI configurator |

---

## III. Export Pipeline & Native Runtime

### Architecture: Three Layers

**Layer 1: Interchange Format (what Storyarn exports)**

```
storyarn_export/
|- manifest.json          # version, metadata
|- flows/                 # dialogue trees + logic
|- variables/             # game state definitions
|- conditions/            # rules
|- instructions/          # mutations
|- characters/            # character sheets
|- scenes/                # scene layouts
|- animations/            # Spine/asset references
|- localization/          # translated texts
|- mechanics/             # system configurations
|- assets/                # or asset references
```

Already have `Exports` context with `DataCollector`, `Serializer`, etc. This extends what exists.

**Layer 2: Native Runtime (Rust)**

A core runtime that:
- Loads Storyarn export
- Evaluates conditions
- Executes instructions (mutates variables)
- Navigates flow graph (next node, responses, branches)
- Manages game state
- Runs configured mechanics

```
storyarn-runtime (Rust)
|- flow_engine.rs        # navigate node graph
|- variable_store.rs     # game state
|- condition_eval.rs     # evaluate conditions
|- instruction_exec.rs   # execute instructions
|- expression_eval.rs    # evaluate formulas
|- localization.rs       # resolve texts by language
|- scene_manager.rs      # scene/character data
|- mechanics/             # pluggable mechanic systems
```

**Layer 3: Engine Plugins (bindings)**

| Engine | Binding | Integration |
|---|---|---|
| Unity | C# via C FFI | `.dll`/`.so` native + C# wrapper |
| Unreal | C++ direct | Rust -> C FFI -> C++ plugin |
| Godot | GDExtension | Rust with gdext (official support) |
| Bevy | Native Rust | Direct crate, trivial |

**Why Rust:**
- One codebase, all engines — compiles to native library per platform
- Clean C FFI — Unity and Unreal consume C without issues
- Godot has gdext — first-class Rust bindings
- No garbage collector — doesn't fight Unity/Unreal GC
- Free WebAssembly — web preview compiles to WASM

**Critical architecture decision: Rust as single source of truth**

Instead of maintaining logic in both Elixir and Rust:
1. Rust runtime compiles to **WASM**
2. Story player and debug mode in web **use the WASM**
3. Native plugins use the **same Rust compiled natively**
4. **One implementation**, multiple targets

### Complexity Assessment

| Piece | Difficulty |
|---|---|
| Export format definition | Medium (extends existing Exports context) |
| Rust core runtime | High (replicate conditions/instructions/flows logic) |
| Expression evaluator in Rust | Medium-High (port FormulaEngine from Elixir) |
| Godot plugin | Medium (gdext is ergonomic) — build first |
| WASM for web preview | Medium (Rust compiles to WASM with minimal changes) |
| Unity plugin | High (C FFI + C# wrapper + editor UI) |
| Unreal plugin | Very High (C++ is tedious, UE plugin system is complex) |

### Recommended Build Order

1. Define export format (most important — it's the contract)
2. Rust runtime with flow engine + variables + conditions
3. Godot plugin first (easiest, validates architecture)
4. WASM to replace web story player
5. Unity plugin (largest market)
6. Unreal plugin (last, most complex)

---

## IV. Platform Features

### A. Public Wiki (Fandom-Style)

**Not Notion/Confluence. This is community-facing fandom.**

- Subdomain per game: `wiki.mygame.storyarn.com`
- Auto-generated from structured data (characters, lore, maps, items)
- Community can expand and edit (like fandom.com)
- Designer controls what's published vs internal
- Interactive maps with zone names, connections
- Ad-supported on free tier

**Flywheel:**
- Designer uses Storyarn -> publishes wiki
- Players visit wiki -> discover Storyarn
- Ads fund free tier
- More games -> more wikis -> more traffic

**Complexity:** Low — exposing existing structured data with a public layout.

### B. Auto-Generated GDD

- Pulls from all existing data: characters, flows, variables, mechanics, scenes
- LaTeX already integrated
- Professional document layout
- Living document — updates as the project evolves
- Exportable as PDF

**Complexity:** Low-Medium — connecting existing data to a document template.

### C. External Tool Integration

**Pattern: Storyarn creates tasks in YOUR tools, doesn't replace them.**

- "Create task" button on any Storyarn entity
- Modal: choose Linear/Jira/Trello project
- Auto-generated description + link back to Storyarn + attached images
- Webhook for bidirectional status sync
- In Storyarn: see task status without leaving

**Deep links bidirectional:** Every Storyarn entity has a stable URL. Linear/Jira comments can link directly to a specific dialogue node. From Storyarn, see all linked tasks for any entity.

**Complexity:** ~1 week for first integration, days for each subsequent one. Same pattern repeated.

### D. Production Pipeline

Once integrations + entity data exist, the pipeline emerges naturally:

```
Character sheet in Storyarn
  -> "Create art task" -> Linear (concept art brief + AI reference images)
  -> Art complete, uploaded to Storyarn assets
  -> "Create 3D modeling task" -> Linear (final designs + notes for 3D artist)
  -> "Create animation task" -> Linear (personality notes + Spine reference)
  -> "Create voice task" -> Linear (voice direction sheets + script)
```

Each step links back to the character in Storyarn. The designer sees the full pipeline status on the entity.

### E. AI Content Generation

- Character concept art from sheet descriptions
- Scene backgrounds from zone/layer descriptions
- Asset variations and iterations
- Brief generation for artists

**Complexity:** Low — API calls to image generation services, similar to existing DeepL integration pattern.

---

## V. Proposed New Features

### 1. Playtesting Analytics — HIGH PRIORITY

Share a link, testers play in exploration mode, Storyarn records everything:

| Metric | Value |
|---|---|
| Narrative funnel | Of 100 testers, how many reached the end, where they dropped off |
| Decision heatmap | What % chooses each dialogue response |
| Time-per-node | Which dialogues are read fast (boring) vs re-read (confusing/interesting) |
| Branch discovery | What % of content was seen by at least one tester |
| Stuck detection | Where testers loop or give up |
| Shareable reports | Designer generates a report and shares via link |

**Implementation:** Log events during exploration mode (`INSERT` per interaction) + dashboard views.

**Why this is gold:** No narrative design tool offers this. Designers currently playtest by watching over someone's shoulder. This gives them data at scale.

### 2. Branching Visualizer / Story Map

A high-level view showing ALL possible paths through the game. Not individual flows — the meta-flow.

- "If the player does X in chapter 2, this unlocks Y in chapter 5"
- Overlay playtesting data: "73% of testers never saw this branch"
- Identify dead-end paths, unreachable content, narrative bottlenecks

**Why:** articy attempts this and fails. No tool does it well.

### 3. Voice Direction Sheets

For each dialogue line, the designer adds direction for voice actors:
- Emotion, intensity, pacing
- Audio reference clips
- Context (what just happened in the story)
- Technical notes (whisper, shout, crying)

Export as formatted scripts for recording sessions. Actors get full context without playing the game.

**Why:** Already have flows + dialogues + localization + audio assets. Connecting the dots.

### 4. Consistency Checker (AI) — HIGH PRIORITY

AI analyzes the entire project and detects:

| Issue | Example |
|---|---|
| Plot holes | Character dies in branch A but appears in branch B |
| Dead variables | Variables set but never read |
| Unreachable content | Dialogues that no path leads to |
| Missing references | Characters referenced that don't exist |
| Tone inconsistency | Different writing styles between team members |
| Broken conditions | Conditions referencing deleted variables |
| Circular paths | Flow loops with no exit condition |

**Why this is a must-have:** Narrative designers spend weeks manually hunting inconsistencies. This alone justifies the subscription.

### 5. Live Collaboration in Playtesting

Designer and tester in the same session:
- Designer sees what the tester does in real-time
- Designer takes notes anchored to the exact moment in the playtest
- Can pause and ask questions
- Recording of the full session for later review

**Why:** Like Figma's "observe mode" but for game prototypes. Collaboration infrastructure already exists.

### 6. Asset Brief Generator

From a character sheet, AI generates a complete brief for artists:
- Visual description compiled from all sheet fields
- Mood board suggestions
- Color palette based on character traits
- Technical constraints (sprite size, animation count needed)
- Reference images (AI-generated concepts)

The artist receives a professional document, not a Slack message saying "make me an elf."

### 7. Create on Reference — Inline Entity Creation

**Core concept:** The user types a dot-notation path that doesn't exist, and the system creates it. Like `mkdir -p` for game design entities. The designer thinks and the tool follows — no context switching.

**Example 1: Speaker in dialogue node**

```
User types: characters.main-characters.elias

System:
1. Parse path: ["characters", "main-characters", "elias"]
2. Look up sheet with shortcut "characters" → exists?
   - Yes → find child "main-characters" → exists?
     - Yes → find child "elias" → exists?
       - No → create sheet "Elias" inside main-characters
     - No → create folder "Main Characters", then "Elias" inside
   - No → create entire hierarchy
3. Assign created sheet as speaker
```

**Example 2: Variable in condition/instruction builder**

```
User types: elias.has_key

System:
1. Find sheet "elias" → found
2. Find block "has_key" in elias → doesn't exist
3. Infer type from name + context:
   - Name "has_key" → suggests boolean (has_*, is_*, can_*)
   - Used in condition with true/false → boolean confirmed
4. Create block "has_key" type boolean on sheet elias
5. Use it in the condition
```

**Type inference — dual strategy (name + context):**

By name pattern:

| Pattern | Inferred Type | Confidence |
|---|---|---|
| `has_*`, `is_*`, `can_*`, `was_*` | boolean | High |
| `count_*`, `num_*`, `*_count`, `health`, `level`, `age` | number | Medium |
| `name`, `title`, `description`, `*_text` | text | Medium |
| Everything else | Unknown | Show modal |

By usage context:

| Context | Inferred Type |
|---|---|
| Compared with `true`/`false` | boolean |
| Compared with a number | number |
| Operator `greater_than`, `less_than` | number |
| Operator `contains`, `starts_with` | text |
| Operator `is_empty`, `is_nil` | Ambiguous — show modal |

When both agree, create without asking. When they conflict or are ambiguous, show a quick one-click confirmation modal.

**Accidental creation prevention:**

- **Fuzzy matching first.** Before creating, search for similar: "Did you mean `has_key`?"
- **Undo.** Ctrl+Z undoes the creation
- **Visual indicator.** Input changes color or shows a "NEW" badge when about to create

**Hierarchy rules:**
- Intermediate folders are normal sheets without blocks
- User can add blocks to them later
- A "folder" is simply a sheet that has children

**Where it applies:**

| Context | What Gets Created | Example |
|---|---|---|
| Flow → dialogue speaker | Sheet (character) | `characters.elias` |
| Flow → condition variable | Block on existing sheet | `elias.has_key` |
| Flow → instruction variable | Block on existing sheet | `elias.gold` → number |
| Scene → pin reference | Sheet | `items.magic-sword` |
| Scene → zone trigger | Flow | `chapter1.tavern-dialogue` |
| Condition → sheet reference | Full sheet | `factions.guild` |

**Project settings toggle:**

| Mode | Behavior | Target |
|---|---|---|
| **Creative** (default) | Create on reference active | Indies, rapid prototyping |
| **Strict** | Only reference existing entities, autocomplete only | AAA, large teams |

**Technical implementation:**

```elixir
defmodule Storyarn.Shared.InlineCreator do
  @doc """
  Resolves a dot-notation path, creating missing entities as needed.
  Returns {:ok, entity} | {:confirm, type_options} | {:suggest, similar}
  """
  def resolve_or_create(path, project_id, opts \\ [])

  # opts:
  #   context: :speaker | :condition | :instruction
  #   operator: "greater_than" | "is_true" | ...
  #   value: "50" | "true" | ...
  #   enabled: true/false (from project settings)
end
```

JS side: extend existing search inputs (combobox/searchable select):
- Exact match → select
- Fuzzy match → suggest
- No match + creative mode → show "Create `elias.has_key`" option with inferred type
- User confirms with Enter or click

**Assessment:**

| Aspect | Rating |
|---|---|
| User value | **Very high** — eliminates constant friction |
| Implementation complexity | **Medium** — parsing/creation is simple, fuzzy + confirmation UX is the complex part |
| Risk | **Low with toggle** — enterprises disable it, indies enjoy it |
| Competitive differentiator | **High** — articy has nothing like this |

### 8. Avatar Gallery — Multi-Avatar System for Sheets

**Core concept:** The sheet avatar evolves from a single image to an ordered list of images. Two management modes: a quick inline film strip (carrete) and a full-size gallery modal for detailed editing.

**Why:** Character portraits with expressions are standard across RPGs, visual novels, adventure games, and tactical RPGs. Persona 5 uses 12-20 per character, Fire Emblem uses 8-12, RPG Maker defaults to 8. articy has AlternatePortraits but with poor UX — no visual preview in flows, no inline editing.

**Mode 1: Film Strip (inline in sheet)**

Quick management: add, reorder, select default. No name editing, no metadata. Pure speed.

```
┌─────────────┐
│    [img]    │
├─────────────┤
│  ★ [img]   │  ← default
├─────────────┤
│    [img]    │
├─────────────┤
│   + Add     │
├─────────────┤
│  Gallery    │  ← opens modal
└─────────────┘
```

Film strip actions: add image, reorder (drag), select default (click), delete (hover → X), open gallery.

**Mode 2: Gallery Modal (full-size)**

Detailed management with two sub-views:

Grid view — all avatars visible, click inline to name, drag to reorder.

Single view — click any image from grid to see full-size, with editable fields below:
- **Name** (optional) — normalized with `variablify` (e.g., "Angry Face" → `angry_face`)
- **Notes** (optional) — free text for art direction, actor notes, context
- Navigation arrows between images
- "Set as default" button
- Delete button

**Editing capabilities per mode:**

| Action | Film Strip | Gallery Grid | Gallery Single |
|---|---|---|---|
| Add image | Yes | Yes | No |
| Reorder | Drag | Drag | Arrows ← → |
| Select default | Click | Click | Button |
| Delete | Hover → X | Hover → X | Button |
| Edit name | No | Click inline | Input field |
| Edit notes/metadata | No | No | Yes |
| View full size | No | No | Yes |

**In dialogue nodes:**

Click the avatar on the dialogue node → selector shows all avatars from the speaker's gallery:
- Named avatars show name + thumbnail
- Unnamed avatars show thumbnail only
- Default is always labeled "default"
- If no avatar is selected for a node, the sheet's default avatar is used

**Data model:**

```
SheetAvatar (new table)
  - sheet_id (required, belongs_to Sheet)
  - asset_id (required, belongs_to Asset)
  - name (string, optional, variablified)
  - notes (text, optional)
  - position (integer)
  - is_default (boolean, default false)

Dialogue node data:
  - avatar_id (nullable — if null, use sheet default)
```

New table (not JSON field) for: queryability, DB-level ordering, clean schema migration.

**Design principles:**
- **Zero overhead if unused** — single avatar works exactly as today
- **No imposed semantics** — images can represent emotions, costumes, ages, angles — user decides
- **Modal absorbs future complexity** — tags, audio references, or any new fields get added to single view without changing the strip
- **Exportable** — name + notes travel in the export, engine plugins can auto-map expressions

**Assessment:**

| Aspect | Rating |
|---|---|
| User value | **High** — standard industry need, every narrative game uses portraits |
| Implementation complexity | **Medium** — new table, film strip component, gallery modal |
| Risk | **Very low** — backwards compatible, optional feature |
| Competitive differentiator | **High** — articy's AlternatePortraits is clunky, no visual preview in flows |

---

## VI. Monetization Angles

| Revenue Stream | Source |
|---|---|
| Subscriptions | Studios paying per-seat or per-workspace |
| Wiki ads | Free-tier wikis with ad support |
| Mechanics marketplace | Community-created mechanic configurations (revenue share) |
| AI usage | Token-based for generation features |
| Engine plugins | Free (drives platform adoption) |
| Enterprise | SSO, audit logs, dedicated support |

---

## VII. Strategic Build Order

```
PHASE 1 — Foundation (current)
  Complete and polish: narrative, localization, collaboration, assets
  Exploration mode improvements
  First paying users

PHASE 2 — Differentiation
  Playtesting analytics
  Consistency checker (AI)
  Export format definition
  AI content generation
  Voice direction sheets

PHASE 3 — Integration
  External tool integrations (Linear, Jira, Trello)
  Auto-generated GDD
  Production pipeline (emerges from integrations)
  Branching visualizer

PHASE 4 — Platform
  Public wikis (fandom-style)
  Interactive maps
  Asset brief generator
  Live collaboration in playtesting

PHASE 5 — Engine Pipeline
  Rust runtime
  Godot plugin (validates architecture)
  WASM web preview
  Unity plugin
  Configurable mechanics (first systems)

PHASE 6 — Ecosystem
  Mechanics marketplace
  Unreal plugin
  Community features
  Enterprise tier
```

---

## VIII. What Makes This Worth Paying For

Today, a 5-15 person indie studio uses:
- articy or Yarn Spinner (narrative): $200-800/year
- Figma (UI/concepts): $15/month/person
- Notion (GDD): $10/month/person
- Jira/Linear (tasks): $10/month/person
- Google Sheets (variables, balance): free but chaotic
- Crowdin (localization): $50-500/month

**Total: $500-2000/month in disconnected tools.**

Storyarn doesn't replace all of them. It replaces the narrative + design tools, integrates the project management tools, and adds capabilities none of them have (playtesting analytics, consistency checking, auto-generated GDD, public wikis).

The character you design is the same one that appears in the flow, in the wiki, in the art task in Linear, in the GDD, in the voice recording script. **That connection is what no competitor can replicate by combining separate tools.**

### Impact Assessment

**Pessimistic:** 500-1000 paying users, $10-30k/month. Viable indie business.

**Optimistic:** 5000-20000 paying users at $50-200/month per studio. $250k-4M/year. Wikis generate organic traffic. Mechanics marketplace creates network effects. Each published game advertises Storyarn through its wiki.

**What separates the two:** Whether the integration between features feels magical or bolted-on.
