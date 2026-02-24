# Future Features

> **Purpose:** Document planned features that are not in the current implementation scope
>
> **Last Updated:** February 9, 2026

---

## Copy-Based Drafts (Screenplays & Flows)

> **Dependency:** Requires Screenplay Tool (Phase 1 schema ready) + Flow system
> **Priority:** Must Have — essential for creative iteration workflows
> **Schema fields:** Already included in Screenplay migration (draft_of_id, draft_label, draft_status)
> **Related:** `docs/plans/SCREENPLAY_TOOL.md` — Design Decision D8

### Concept

Drafts allow writers and designers to create **alternative versions** of a screenplay or flow without losing the current version. Think of it as git branches for non-technical creative users.

A draft is a **full deep clone** of the original entity — it's an independent copy that can be edited, compared, and optionally promoted to replace the original.

### Use Cases

1. **Alternative scenes:** "What if the protagonist takes the dark path instead?"
2. **A/B testing narratives:** Create two versions of a scene, playtest both, keep the better one
3. **Client proposals:** Present multiple approaches for the same scene
4. **Safe experimentation:** Try a radical restructure without risking the working version
5. **Versioned milestones:** Archive the "approved" version before making further edits

### Data Model

#### Schema additions (Screenplay — already in migration)

```elixir
# In screenplays table (fields already present in Phase 1 migration):
add :draft_of_id, references(:screenplays, on_delete: :delete_all)
add :draft_label, :string           # "Alternative ending", "Draft B", etc.
add :draft_status, :string, default: "active"  # "active" | "archived"
```

#### Schema additions (Flow — separate migration when implemented)

```elixir
# Migration: add_draft_fields_to_flows
add :draft_of_id, references(:flows, on_delete: :delete_all)
add :draft_label, :string
add :draft_status, :string, default: "active"

create index(:flows, [:draft_of_id])
```

#### Entity Hierarchy

```
Screenplay "Act 1 Scene 3" (id=10, draft_of_id=nil)     ← ORIGINAL
├── Draft "Dark ending"    (id=15, draft_of_id=10)       ← ACTIVE DRAFT
├── Draft "Happy ending"   (id=16, draft_of_id=10)       ← ACTIVE DRAFT
└── Draft "Archived v1"    (id=17, draft_of_id=10, status=archived)

Flow "Scene 3 Flow" (id=20, draft_of_id=nil)             ← ORIGINAL
├── Draft "With hub routing" (id=25, draft_of_id=20)     ← ACTIVE DRAFT
└── Draft "Linear version"   (id=26, draft_of_id=20)     ← ACTIVE DRAFT
```

### How It Works

#### Creating a Draft

"Create draft" = deep clone of the entity + all its children:

**Screenplay draft:**
1. Clone `screenplay` record → set `draft_of_id` to original's id
2. Clone all `screenplay_elements` → point to new screenplay
3. Preserve `linked_node_id` references (elements still point to same flow nodes)
4. User names the draft (default: "Draft of {original_name}")

**Flow draft:**
1. Clone `flow` record → set `draft_of_id` to original's id
2. Clone all `flow_nodes` → point to new flow, build old→new ID map
3. Clone all `flow_connections` → point to new flow, remap node IDs using the map
4. User names the draft

```elixir
defmodule Storyarn.Screenplays.DraftOperations do
  def create_draft(%Screenplay{} = original, attrs \\ %{}) do
    Repo.transaction(fn ->
      # 1. Clone screenplay
      draft = clone_screenplay(original, %{
        draft_of_id: original.id,
        draft_label: attrs[:label] || "Draft of #{original.name}",
        draft_status: "active"
      })

      # 2. Clone all elements
      elements = Screenplays.list_elements(original.id)
      Enum.each(elements, fn el ->
        clone_element(el, %{screenplay_id: draft.id})
      end)

      draft
    end)
  end
end
```

#### Promoting a Draft

"Promote" = the draft becomes the original, the original becomes an archived draft:

1. Swap `draft_of_id`: original gets `draft_of_id = draft.id`, draft gets `draft_of_id = nil`
2. Original's status → `"archived"`, draft's status → `"active"`
3. All other drafts of the original now point to the promoted draft (update `draft_of_id`)
4. If the original was linked to a flow, the promoted draft inherits the `linked_flow_id`

```elixir
def promote_draft(%Screenplay{draft_of_id: original_id} = draft) when not is_nil(original_id) do
  original = Repo.get!(Screenplay, original_id)

  Repo.transaction(fn ->
    # 1. Original becomes archived draft of the promoted entity
    original
    |> Screenplay.changeset(%{draft_of_id: draft.id, draft_status: "archived", draft_label: "Pre-promotion archive"})
    |> Repo.update!()

    # 2. Draft becomes original
    draft
    |> Screenplay.changeset(%{draft_of_id: nil, position: original.position, parent_id: original.parent_id})
    |> Repo.update!()

    # 3. Redirect other drafts
    from(s in Screenplay, where: s.draft_of_id == ^original_id and s.id != ^draft.id)
    |> Repo.update_all(set: [draft_of_id: draft.id])
  end)
end
```

#### Archiving / Deleting a Draft

- **Archive:** Set `draft_status = "archived"`. Hidden from default view, still accessible.
- **Delete:** Soft delete (set `deleted_at`). Can be restored from trash.

### UI Design

#### Sidebar: Drafts are NOT in the tree

Drafts don't appear in the main sidebar tree. The tree only shows originals (`WHERE draft_of_id IS NULL`).

#### Editor: Draft selector in toolbar

When viewing an original that has drafts, the toolbar shows a dropdown:

```
┌─────────────────────────────────────────────────────────────┐
│ [scroll-text] Act 1 Scene 3    [Original ▼]    [Sync] [⋮]  │
│                                 ┌──────────────────────┐    │
│                                 │ ● Original           │    │
│                                 │ ○ Dark ending        │    │
│                                 │ ○ Happy ending       │    │
│                                 │ ─────────────────    │    │
│                                 │ Archived (1)    ▸    │    │
│                                 │ ─────────────────    │    │
│                                 │ + New Draft          │    │
│                                 └──────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

When viewing a draft:
- Banner at top: "You are editing draft: Dark ending" + [Promote] + [Back to original]
- All editing works identically to the original
- Collaboration works independently per draft

### Cross-Entity Draft Linking

A screenplay draft can have its own `linked_flow_id`, independent of the original:

| Scenario                  | Screenplay         | linked_flow_id            |
|---------------------------|--------------------|---------------------------|
| Original with flow        | Scene 3 (original) | → Flow Scene 3 (original) |
| Draft with same flow      | Scene 3 draft A    | → Flow Scene 3 (original) |
| Draft with own flow draft | Scene 3 draft B    | → Flow Scene 3 draft X    |
| Draft unlinked            | Scene 3 draft C    | → nil                     |

This is handled naturally by the existing `linked_flow_id` field — no special logic needed.

**Constraint:** The unique index on `linked_flow_id` means only ONE screenplay entity (original or draft) can be linked to a given flow at a time. This prevents sync conflicts.

### Implementation Phases

#### Draft Phase 1: Core (Screenplay only)
- Deep clone function for screenplays + elements
- Draft CRUD: create, archive, delete, restore
- Draft selector dropdown in screenplay editor toolbar
- Draft banner when editing a draft
- `list_drafts/1` query
- Filter drafts from sidebar tree

#### Draft Phase 2: Promote & Compare
- Promote draft to original
- Side-by-side diff view (element-level comparison)
- Draft history timeline

#### Draft Phase 3: Flow Drafts
- Add `draft_of_id`, `draft_label`, `draft_status` to flows migration
- Deep clone for flows + nodes + connections
- Draft selector in flow editor toolbar
- Cross-entity linking (screenplay draft ↔ flow draft)

#### Draft Phase 4: Advanced
- Merge: cherry-pick elements from a draft into the original
- Batch drafts: create draft of entire flow+screenplay pair simultaneously
- Draft comments/annotations: "This version changes the motivation for..."

### Impact Assessment

| Component         | Impact   | Notes                                           |
|-------------------|----------|-------------------------------------------------|
| Screenplay schema | None     | Fields already in migration                     |
| Flow schema       | Low      | One migration to add 3 fields                   |
| Sidebar tree      | None     | Already filters `draft_of_id IS NULL`           |
| CRUD operations   | Low      | Deep clone is the main new function             |
| Sync engine       | None     | Works via existing `linked_flow_id`             |
| Collaboration     | None     | Each draft is an independent entity             |
| Editor UI         | Medium   | Draft selector dropdown + banner                |
| Queries           | Low      | Add `WHERE draft_of_id IS NULL` to list queries |

**Total difficulty: Medium.** The bulk of the work is the deep clone function and the toolbar UI. The architecture supports it cleanly because a draft IS a full entity, not a layer on top.

### Competitive Reference

- **articy:draft:** Has a "Working Copies" feature where you can clone packages for parallel editing. Merge is manual.
- **Google Docs:** "Suggested edits" mode (inline, not full copies). Different mental model.
- **Git:** Full branch-and-merge. Most powerful but requires technical knowledge.
- **Figma:** "Branching" feature (beta). Deep copy of entire file with merge capability.

Storyarn's copy-based approach is closest to articy's Working Copies — simple, predictable, and no merge conflicts (you choose which version to keep).

---

## Variable State Timeline (Sheet-Side View)

> **Dependency:** Requires `variable_references` table (done) + Sheet UI extension
> **Prerequisites completed:** Instruction nodes, condition nodes, variable tracking, flow debugger
> **Partially superseded:** Options B & C are now covered by the Flow Debugger

### Concept

A sheet-side view that answers: **"Where and how does this variable change across all flows?"**

This is the **remaining piece** of the original Variable State Timeline feature. The flow-side features (originally planned as Options B & C) have been implemented as part of the Flow Debugger:

- **Option B (Flow State Inspector)** → Implemented as the debugger's Variables tab (shows current/initial/previous values at the current node, with filtering and editing)
- **Option C (Interactive Simulation)** → Implemented as the Flow Debugger itself (step through flows, choose responses, auto-play, cross-flow call stack, breakpoints)
- **Option A (Sheet Timeline Tab)** → Not yet implemented — this is what remains

### What Remains: Sheet Timeline Tab

The `variable_references` table already tracks which flow nodes read/write which variables. The missing piece is a UI on the Sheet view that visualizes this:

```
┌─────────────────────────────────────────────────────────────┐
│ [Content] [References] [Timeline]                           │
├─────────────────────────────────────────────────────────────┤
│ VARIABLE CHANGES                                            │
│                                                             │
│ health (initial: 100)                                       │
│ ├─ Chapter 1 / Node "Fight"    → writes (-30)               │
│ ├─ Chapter 1 / Node "Heal"     → writes (+30)               │
│ └─ Chapter 2 / Node "Ambush"   → writes (-50)               │
│                                                             │
│ mood (initial: "neutral")                                   │
│ ├─ Chapter 1 / Node "Victory"  → writes ("happy")           │
│ └─ Chapter 2 / Node "Betrayal" → writes ("angry")           │
│                                                             │
│ health (reads)                                              │
│ ├─ Chapter 1 / Node "Check HP" → reads (condition)          │
│ └─ Chapter 2 / Node "Death?"   → reads (condition)          │
└─────────────────────────────────────────────────────────────┘
```

### Implementation

The data layer already exists:

```elixir
# Already implemented:
Storyarn.Flows.VariableReferenceTracker.get_variable_usage(block_id, project_id)
# Returns: [%{flow_name, node_id, node_type, kind: "read"|"write", source_sheet, source_variable}]
```

What's needed:
1. **Sheet UI:** Add "Timeline" or "Usage" tab to the sheet editor
2. **Query:** Group variable_references by variable, sorted by flow
3. **Navigation:** Click a reference to jump to the flow node
4. **Stale detection:** Show warning if a variable reference points to a renamed/deleted variable

### Complexity Considerations

- **Cross-flow jumps:** Variable changes might span multiple flows — show all flows
- **Static analysis only:** This shows where variables CAN change, not runtime values (the debugger handles runtime)
- **Performance:** Large projects with many flows could have many references — pagination or lazy loading

---

## Expression Text Mode (Power User Mode)

> **Dependency:** Instruction Node — shipped and tested
> **Priority:** P1 — ready to implement when prioritized

### Concept

An alternative text-based input mode for instruction and condition nodes, where experienced users can type expressions directly instead of using the visual sentence-flow builder.

### Syntax Example

```
mc.jaime.health += 10
mc.zelda.hasMasterSword = true
mc.link.health = mc.link.health + items.potion.value
```

### Why Defer

The visual sentence-flow builder is Storyarn's core UX differentiator. Adding a text mode before it's polished would split focus. However, competitive research shows that power users of articy:draft, Ink, and Yarn Spinner are consistently faster with text input for bulk operations.

### When to Revisit

The visual builder is now shipped. This becomes relevant once user feedback indicates that power users find the visual builder slow for bulk operations.

### Implementation Sketch

- Toggle button on the instruction panel: "Visual" / "Expression"
- Expression mode: single textarea with autocomplete (like articy:expresso)
- Autocomplete triggers on typing sheet shortcuts or variable names
- Syntax highlighting: sheet shortcuts in blue, variable names in green, operators in orange
- On save, parse the expression into the same `assignments` data structure
- Both modes read/write the same underlying data — switching is lossless

### Competitive Reference

articy:draft's expresso language (C#-like syntax with autocomplete and syntax highlighting). Dialogue System for Unity's Lua editor with wizard-generated code.

---

## Slash Commands in Value Input

> **Dependency:** Instruction Node — shipped
> **Priority:** P3 — only if user demand emerges

### Concept

Typing `/sheet` in a value input field switches it to a sheet variable selector. Typing `/value` switches back to literal value input.

### Example Flow

1. User is in a value input field (expects a number)
2. Types `/sheet` → field transforms into a sheet+variable combobox
3. Selects `global.quests.masterSwordDone` → value is set as variable reference
4. To go back: types `/value` → field transforms back to literal input

### Why Defer

The `123`/`{x}` toggle button in the visual builder achieves the same functionality with better discoverability. Slash commands require memorization and are invisible to new users. No competing narrative design tool implements this pattern.

### When to Revisit

If user testing reveals that the toggle button interrupts flow for keyboard-centric users who never want to touch the mouse. Could be implemented as a keyboard shortcut (e.g., `Ctrl+Shift+V` to toggle value type) instead of slash syntax.

### Competitive Reference

Inspired by Notion's `/` command palette and VS Code's command palette, but those operate at document/editor level, not inside individual form fields. No narrative design tool uses this pattern.

---

## Conditional Assignments ("When...Change...To")

> **Dependency:** Instruction Node + Condition Builder — both shipped
> **Priority:** P2 — lightweight "only if" version first

### Concept

A single instruction row that combines a condition check with a variable assignment, reading like natural language:

```
When  [mc.zelda]·[hasMasterSword]  is  [true]  then  Set  [mc.link]·[health]  to  [+50]
```

### Why Defer

This merges two distinct concepts (condition + instruction) into one unit. articy:draft explicitly separates these into input pins (conditions) and output pins (instructions), and this separation is considered one of their best design decisions. The flow editor already supports this pattern naturally: Condition Node → Connection → Instruction Node.

Problems with merging:
- Complicates the data model (each assignment optionally contains a full condition)
- Confuses the mental model ("is this a condition or an instruction?")
- Doubles the complexity of the variable reference tracker
- Makes the sentence-flow UI significantly more complex

### When to Revisit

If users consistently create simple one-condition → one-assignment flows and report that creating two separate nodes feels like overhead.

### Lightweight Alternative

A simpler version that adds an "only if" toggle on each assignment row:

```
Set  [mc.link]·[health]  to  [+50]   only if [mc.zelda]·[hasMasterSword] is [true]
```

This adds a collapsible "only if" clause to individual assignments without creating a full condition builder inside the instruction node.

### Competitive Reference

No mainstream narrative tool merges conditions and instructions this way. Ink uses inline conditions in choices (`* { hasKey } [Use key]`) but these gate choices, not variable assignments.

---

## Competitive Analysis: Instruction/Variable Systems

> **Date:** February 6, 2026
> **Purpose:** Informs UX decisions for Storyarn's instruction builder

### Market Landscape

| Tool                      | Approach                           | Visual Builder?   | Non-Programmer Friendly?              |
|---------------------------|------------------------------------|-------------------|---------------------------------------|
| **articy:draft**          | C#-like text with autocomplete     | No                | Medium — C# syntax is barrier         |
| **Twine (Harlowe)**       | Functional macros `(set: $v to x)` | No                | Easy for basics, steep for logic      |
| **Ink (Inkle)**           | Custom syntax (`~ x = 2`)          | No                | Writer-friendly but still code        |
| **Yarn Spinner**          | Tag-based `<<set $v to x>>`        | No                | Screenplay-like, accessible           |
| **Chat Mapper**           | Lua + dropdowns                    | Partial           | Lua quirks frustrate users            |
| **Dialogue System Unity** | Lua + **full dropdown wizard**     | **Yes**           | **Most accessible** for complex logic |
| **Fungus**                | 100% visual blocks                 | **Yes**           | Most accessible but tedious at scale  |

### Key Findings

1. **No standalone narrative design tool** has a first-class visual instruction builder. Dialogue System for Unity has the closest equivalent, but it's a Unity plugin.

2. **The #1 pain point** across all tools is **remembering variable names**. Tools with autocomplete/dropdowns win.

3. **Visual builders become tedious at scale** (Fungus). Keyboard-driven flow mitigates this.

4. **Text editors exclude non-programmers** (articy, Ink). Sentence-flow UI bridges the gap.

5. **Writers prefer inline variable syntax** over separate GUI panels.

6. **Academic finding:** A Journal of Creative Technologies study found providing **multiple representations** (visual AND text) is the winning approach.

### Storyarn's Position

Storyarn occupies an **unserved niche**: a standalone narrative design tool with a visual instruction builder that feels like writing.

| Segment              | Competition               | Storyarn Advantage                        |
|----------------------|---------------------------|-------------------------------------------|
| Text scripting       | articy, Ink, Yarn Spinner | Accessible to non-programmers             |
| Pure visual blocks   | Fungus                    | Scales better, less tedious               |
| Hybrid wizard + code | Dialogue System for Unity | Standalone (not engine-locked), modern UX |

### What Ships Commercial Games

- **articy:draft** → Pillars of Eternity, Broken Age
- **Ink** → 80 Days, Heaven's Vault, Sable, Citizen Sleeper
- **Yarn Spinner** → Night in the Woods, A Short Hike
- **Dialogue System for Unity** → Widely used in Unity indie/AA

All use text-based or hybrid approaches. No commercial game of note uses a pure visual block system for complex narrative logic.

---

## AI Image Gallery

> **Dependency:** Requires Assets system + AI integration

### Concept

A block type that displays a gallery of AI-generated images for a page (character, location, item). The AI uses the page's blocks as context to generate relevant imagery.

### Use Cases

1. **Character Visualization:** Generate portraits based on character description
2. **Location Art:** Generate environment concepts based on location details
3. **Item Concepts:** Generate item variations based on properties
4. **Mood Boards:** Generate thematic imagery for quests/chapters

### Architecture

```
AI Gallery System
├── Gallery Block
│   ├── Block type: "ai_gallery"
│   ├── Config: {label, style_preset, aspect_ratio}
│   ├── Value: {images: [{asset_id, prompt, generated_at}]}
│   └── Max images per gallery (configurable, e.g., 12)
│
├── Context Builder
│   ├── Collect sheet blocks as context
│   │   ├── name, description (text/rich_text blocks)
│   │   ├── attributes (select, multi_select blocks)
│   │   └── related entities (reference blocks)
│   ├── Build structured prompt
│   └── Apply style presets
│
├── AI Image Generation
│   ├── Provider abstraction (OpenAI, Stability, Replicate)
│   ├── Async job processing (Oban)
│   ├── Rate limiting per project/workspace
│   └── Cost tracking
│
├── Gallery UI
│   ├── Grid display of generated images
│   ├── Generate button with style options
│   ├── Regenerate individual images
│   ├── Delete images
│   ├── Set as page avatar/banner
│   └── Download/export options
│
└── Storage
    ├── Generated images saved to Assets
    ├── Prompt history preserved
    └── Metadata: model, settings, generation time
```

### Context Building Example

```
Sheet: Jaime (Character)
Blocks:
  - name: "Jaime"
  - race: "Human"
  - class: "Warrior"
  - age: "35"
  - description: "A battle-scarred veteran with a kind heart"
  - personality: ["brave", "loyal", "stubborn"]

Generated Prompt:
"Portrait of Jaime, a 35-year-old human warrior.
Battle-scarred veteran with a kind heart.
Personality: brave, loyal, stubborn.
Style: fantasy character portrait, detailed, painterly"
```

### UI Mockup

```
┌─────────────────────────────────────────────────────────────┐
│ AI Gallery                                    [⚙️ Config]   │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐            │
│ │         │ │         │ │         │ │   ＋    │            │
│ │  [img]  │ │  [img]  │ │  [img]  │ │         │            │
│ │         │ │         │ │  ⭐     │ │ Generate│            │
│ └─────────┘ └─────────┘ └─────────┘ └─────────┘            │
│                                                             │
│ [Generate New] [Style: Fantasy Portrait ▼]                  │
└─────────────────────────────────────────────────────────────┘

On image hover:
┌─────────────────────────────────────────────────────────────┐
│ [Set as Avatar] [Set as Banner] [Regenerate] [Delete]       │
└─────────────────────────────────────────────────────────────┘
```

### Style Presets

| Preset              | Description                | Best For          |
|---------------------|----------------------------|-------------------|
| Fantasy Portrait    | Detailed character art     | Characters        |
| Environment Concept | Wide landscape/interior    | Locations         |
| Item Render         | Clean object on neutral BG | Items             |
| Pixel Art           | Retro game style           | Retro games       |
| Anime               | Anime/manga style          | Visual novels     |
| Realistic           | Photo-realistic            | Modern settings   |
| Sketch              | Concept sketch style       | Early development |

### Configuration Options

```elixir
%{
  label: "Character Portraits",
  style_preset: "fantasy_portrait",
  aspect_ratio: "1:1",        # 1:1, 16:9, 9:16, 4:3
  max_images: 12,
  auto_context: true,         # Use sheet blocks as context
  custom_prompt_suffix: "",   # Additional prompt text
  negative_prompt: "blurry, low quality"
}
```

### Cost Management

- Credits system per workspace/project
- Different costs per model/quality
- Generation limits (daily/monthly)
- Admin controls for enabling/disabling

### Implementation Phases

1. **Provider Integration**
   - Abstract AI image provider interface
   - Implement OpenAI DALL-E adapter
   - Implement Stability AI adapter (optional)

2. **Gallery Block Basic**
   - Block type with simple grid
   - Manual prompt entry
   - Save to Assets

3. **Context Builder**
   - Collect sheet blocks
   - Build prompts automatically
   - Style preset application

4. **Advanced Features**
   - Image variations (regenerate similar)
   - Inpainting/editing
   - Batch generation
   - Cost tracking dashboard

### Privacy & Legal Considerations

- Clear user consent for AI generation
- Option to disable AI features
- Generated content ownership terms
- Content moderation (NSFW filtering)
- Data retention policies

---

## Sheet Templates

> **Status:** Discussed but deferred - revisit after Phase 7.5

### Concept

Reusable sheet structures with predefined blocks. Create a "Character" template, then create characters from it.

### Briefly Discussed

- Templates would define which blocks a sheet type has
- Similar to articy:draft's template system
- Could include default values
- Possibly inheritable/extendable

### Open Questions

- How do templates relate to shortcuts?
- Can a sheet's template be changed after creation?
- How to handle template updates (sync to existing sheets?)
- Versioning for templates?

*To be fully designed when the feature is prioritized.*

---

## Features System (Reusable Property Groups)

> **Status:** Research needed - Study articy:draft's Feature system
>
> **Priority:** Medium - Would enhance Sheet Templates significantly

### Concept

A "Feature" is a reusable group of properties (blocks) that can be composed into multiple templates. Instead of defining all blocks per template, you define Features once and combine them.

**articy:draft's Approach:**
```
Feature "BasicInfo"     = [name, description, icon]
Feature "CombatStats"   = [health, attack, defense, speed]
Feature "MerchantInfo"  = [inventory, buy_prices, sell_prices]
Feature "DialogueActor" = [voice_actor, portrait, dialogue_color]

Template "Character"    = BasicInfo + CombatStats + DialogueActor
Template "Merchant NPC" = BasicInfo + CombatStats + MerchantInfo + DialogueActor
Template "Shop"         = BasicInfo + MerchantInfo (no combat!)
Template "Monster"      = BasicInfo + CombatStats (no dialogue)
```

### Benefits

1. **DRY (Don't Repeat Yourself):** Change "CombatStats" once → all characters, merchants, and monsters update
2. **Consistency:** Same property names across entity types
3. **Flexibility:** Mix and match features for different entity types
4. **Discoverability:** "What features does a Merchant have?" is immediately clear

### Questions to Research

1. **How does articy handle Feature updates?**
   - If you add a property to a Feature, what happens to existing entities?
   - Can you remove properties from a Feature safely?

2. **Feature inheritance?**
   - Can Features extend other Features?
   - `Feature "AdvancedCombat" extends "CombatStats" + [critical_chance, dodge]`

3. **Conditional Features?**
   - Can a template have optional Features?
   - "Character may have MerchantInfo (if they're also a merchant)"

4. **UI/UX for composition:**
   - How do users discover available Features?
   - How do they compose Templates from Features?

### Storyarn Adaptation Ideas

**Option A: Features as Block Groups**
```
Features are saved block configurations:
- "CombatStats" = [{type: number, label: "Health"}, {type: number, label: "Attack"}, ...]

Templates reference Features by ID:
- "Character" = [feature:basic_info, feature:combat_stats, feature:dialogue_actor]
```

**Option B: Features as Sheet Types**
```
Features are special sheets that define blocks:
- Sheet "/features/combat-stats" with blocks [health, attack, defense]

Templates inherit from multiple feature sheets (multiple inheritance)
```

**Option C: Tags + Smart Defaults**
```
Instead of formal Features, use tags and smart defaults:
- Tag a sheet as "combatant" → suggest combat blocks
- Less structured but more flexible
```

### Relationship to Existing Systems

- **Block Variables (7.5):** Features would define which blocks are auto-marked as variables
- **Shortcuts (7.5):** Features might have shortcuts for scripting: `#feature.combat.health`
- **Templates:** Features are the building blocks of Templates

### Next Steps

1. Study articy:draft documentation and tutorials on Features
2. Interview users about their entity organization patterns
3. Prototype simple Feature composition UI
4. Decide on data model (Option A/B/C or hybrid)

*This feature significantly impacts Sheet Templates. Should be researched before finalizing template design.*

---

## Technical Considerations

### Shortcut Auto-Update vs Sheet Versioning

> **Status:** Needs evaluation before implementing versioning (Phase 7.5.5)

**Current Behavior:**
- When a sheet/flow is renamed, its shortcut auto-updates to match the new name
- References are stored by ID (stable), so the actual shortcut text change is transparent
- When rendering a reference, the current shortcut is resolved from the ID

**Versioning Impact:**
When sheet versioning is implemented, consider how shortcut changes should be recorded:

1. **Version snapshots:** Should the shortcut at the time of snapshot be preserved?
   - Pro: Historical accuracy - "what was the shortcut when this version was created?"
   - Con: Adds complexity to version restoration

2. **Restoring versions:** If a user restores version N, should the shortcut also revert?
   - Option A: Yes, restore shortcut too (full restoration)
   - Option B: No, keep current shortcut (partial restoration)
   - Option C: Ask user which to use

3. **Reference resolution in historical versions:**
   - When viewing version N, should references show current names or names-at-version-time?
   - This affects both mentions in rich_text and reference blocks

4. **Conflict handling:**
   - What if restoring a version would create a shortcut conflict?
   - Example: Version 1 had shortcut "hero", current sheet "hero-2" exists

**Recommendation:**
Evaluate these scenarios before implementing versioning. The simplest approach may be:
- Store shortcut in version snapshot (for record)
- On restore, regenerate shortcut from name (avoid conflicts)
- References always resolve to current state (simpler UX)

---

## Dialogue Node Enhancements (Deferred)

> **Core phases (1-4) shipped:** Speaker, stage directions, menu text, audio, technical/localization IDs, response conditions/instructions
> **Related:** See DIALOGUE_NODE_ENHANCEMENT.md for completed phases

### Configurable Node Header Style

**Context:** When a speaker is selected for a dialogue node, the node header displays the speaker's avatar and name. Currently, the header keeps the default dialogue node color.

**Feature Request:** Enhance header customization with options:
- **Default mode** (current): Keep dialogue node color, show avatar + name
- **Banner mode**: Use `Sheet.banner_asset_id` as header background
- **Color mode**: Use speaker's custom color (requires adding color field to Sheet)

**Implementation Options:**

1. **Per-Sheet Setting:**
   ```elixir
   # Add to sheets table
   :header_display_mode  # "banner" | "color"
   :header_color         # hex color when mode is "color"
   ```

2. **Per-Node Override:**
   ```elixir
   # In dialogue node data
   "header_mode" => "auto"  # "auto" | "banner" | "color"
   "header_color" => nil    # Override color
   ```

**UI:**
- Sheet settings: "Header display: [Default ▼] / [Banner ▼] / [Color ▼]"
- Dialogue node (optional): "Override header: [Use sheet default ▼]"

**Design Considerations:**
- Banner backgrounds may cause readability issues with avatar + title
- Need text shadow or overlay for contrast when using banners
- Consider aspect ratio constraints for banner in small node headers

**Priority:** Low - Current default color approach works well for MVP

---

### AI-Generated Menu Text

**Context:** Menu text is a short version of dialogue for space-constrained UI (choice wheels, mobile). Writing both full text and menu text manually is tedious.

**Feature:** Auto-generate menu text from full dialogue using AI.

**User Flow:**
```
┌─────────────────────────────────────┐
│ Text: "I've been waiting for you   │
│        for three long days..."     │
│                                     │
│ Menu Text: [                    ]  │
│            [✨ Generate with AI]   │  ← Click to auto-generate
│                                     │
│ Generated: "I've been waiting"     │
│            [Accept] [Regenerate]   │
└─────────────────────────────────────┘
```

**Implementation:**

1. **Prompt Template:**
   ```
   Summarize this dialogue line into a short phrase (max 6 words)
   suitable for a dialogue choice menu. Keep the essence and tone.

   Full text: "{text}"
   Short version:
   ```

2. **Backend:**
   ```elixir
   def generate_menu_text(full_text) do
     AI.complete(prompt: build_prompt(full_text), max_tokens: 20)
   end
   ```

3. **Batch Generation:**
   - "Generate all menu texts" button for entire flow
   - Only generates for nodes with empty menu_text

**Cost Considerations:**
- Very short completions (~20 tokens output)
- Could use cheaper/faster model (e.g., Claude Haiku)
- Rate limit: X generations per project per day

**Dependencies:**
- AI provider integration (OpenAI, Anthropic, etc.)
- Credits/billing system if usage-based

**Priority:** Medium - Nice productivity boost for dialogue-heavy projects

---

## Flow Debugger — Deferred Enhancements

> **Core debugger:** Implemented and merged to main (Feb 2026)
> **What's done:** Step/step-back/reset, simple breakpoints, cross-flow call stack, variable inspection/editing, auto-play, start node selection, console, history, execution path, resizable panel, canvas visual feedback
> **Status:** These are additive enhancements to the shipped debugger

### Saved Test Sessions

Persist debug configurations to the database for re-use. Users can save a named session with a specific start node, variable overrides, and breakpoints, then reload it later to repeat the same test scenario.

Currently debug state is in-memory only (socket assigns + `DebugSessionStore` Agent for cross-flow navigation). Sessions are lost when the panel is closed.

- **Schema:** `debug_sessions` table with `name`, `start_node_id`, `variable_overrides` (map), `breakpoints` (integer array), `flow_id` (FK)
- **CRUD:** `list_debug_sessions/1`, `get_debug_session!/1`, `create_debug_session/1`, `delete_debug_session/1`
- **Panel UI:** Save button with name input, load dropdown listing saved sessions, delete per session
- **Handler:** Save extracts state from engine, load rebuilds engine with overrides applied

### Conditional Breakpoints

Breakpoints can optionally have a condition expression. Execution only pauses when the condition evaluates to true.

Currently breakpoints are a simple `MapSet.t(integer)` of node IDs — execution always pauses at any breakpoint node.

- Change `breakpoints` from `MapSet.t(integer)` to `%{integer => nil | String.t}` (node_id => condition or nil)
- `at_breakpoint?/1` evaluates condition via `ConditionEval.evaluate_string/2` when present, passes unconditionally when nil
- UI: expandable condition input in the Path tab per breakpoint
- Update canvas breakpoint visuals for conditional (outlined) vs unconditional (filled)

---

## Multi-Image Map Layers

> **Dependency:** Maps system (implemented), Layers system (implemented)
> **Priority:** Medium — closes the biggest gap vs World Anvil
> **Competitive reference:** World Anvil (multiple image layers per map)

### Concept

Allow each map layer to have its own background image, so users can stack multiple images on the same map. This enables use cases like building floors, underdark/overworld, transparent overlays (political borders, climate, wind currents), and before/after views.

Currently a map has a single `background_asset_id`. Layers only control element visibility and fog of war.

### Use Cases

1. **Building floors:** Layer 1 = ground floor, Layer 2 = second floor, Layer 3 = basement
2. **Underdark/Overworld:** Surface map layer with an underground tunnel layer beneath
3. **Transparent overlays:** Semi-transparent political borders, trade routes, or climate maps over a geographic base
4. **Temporal states:** "Before the war" / "After the war" versions of the same region
5. **GM annotations:** A private layer image with DM-only notes drawn directly on a copy of the map

### Data Model

```elixir
# Migration: add_background_to_map_layers
alter table(:map_layers) do
  add :background_asset_id, references(:assets, on_delete: :nilify_all)
  add :background_opacity, :float, default: 1.0
end
```

Each layer can optionally have its own background image. The existing map-level `background_asset_id` remains as the base/default layer image. Layer images render in layer order (by `position`), each as its own `L.imageOverlay`.

### UI

- Layer panel: each layer row gets a small image thumbnail + upload button
- Opacity slider per layer image (for transparent overlays)
- When switching layer visibility, both elements AND the layer's background image toggle together
- Existing fog of war system works naturally: fog covers the layer's image + elements

### Implementation Notes

- Leaflet supports multiple `L.imageOverlay` instances at different z-indexes
- Layer background images share the same coordinate bounds as the map (same width/height)
- Upload reuses existing `AssetUpload` live component
- Export (PNG/SVG) must composite visible layer images in order

---

## Map Element Group Permissions

> **Dependency:** Maps system (implemented), Layers system (implemented), Collaboration system
> **Priority:** Low — relevant once Storyarn has GM/player session features
> **Competitive reference:** World Anvil (Marker Groups with per-group visibility permissions)

### Concept

Allow map element groups (via layers or a new "marker group" concept) to have visibility permissions, so that different users or roles see different pins, zones, and annotations on the same map. This is essential for tabletop RPG sessions where the GM needs to hide certain information from players.

### Use Cases

1. **GM-only markers:** Secret locations, trap markers, hidden NPC positions
2. **Player-specific knowledge:** "Elf lore" pins visible only to the elf character's player
3. **Spoiler prevention:** Hide plot-critical locations until they're discovered in-game
4. **Progressive reveal:** Gradually make markers visible as the party explores

### Design Options

**Option A: Permission tags on layers (simpler)**

Extend the existing layer system with a visibility rule:

```elixir
alter table(:map_layers) do
  add :visibility, :string, default: "all"  # "all" | "owner_only" | "role_based"
  add :visible_to_roles, {:array, :string}, default: []  # ["gm", "player:user_id"]
end
```

Pros: Reuses existing layer infrastructure. Users already group elements by layer.
Cons: One layer = one permission set. Can't have mixed-permission pins on the same layer.

**Option B: Marker groups (more flexible)**

New entity separate from layers:

```elixir
create table(:map_marker_groups) do
  add :scene_id, references(:maps, on_delete: :delete_all), null: false
  add :name, :string, null: false
  add :visibility, :string, default: "all"
  add :visible_to_roles, {:array, :string}, default: []
  timestamps()
end

# Add to pins, zones, annotations:
add :marker_group_id, references(:map_marker_groups, on_delete: :nilify_all)
```

Pros: Orthogonal to layers — an element can be on Layer 1 but in the "GM Secrets" group.
Cons: Another organizational axis to manage.

### Prerequisites

This feature only makes sense once Storyarn has:
- Session/campaign concept (GM running a game for players)
- Player roles beyond project membership (GM vs player vs spectator)
- Real-time map viewing during sessions (players see the shared map)

Without these, there's no one to hide markers from. Defer until session/campaign features are designed.

---

## Other Ideas (Not Yet Planned)

### Search & Query System
- Full-text search across sheets and blocks
- Advanced query language (like articy)
- Saved searches/filters

### Rollups & Aggregations
- Sum/count/average of numeric blocks across sheets
- "Total gold across all characters"
- Dashboard views

### Comments & Annotations
- Comments on sheets/blocks
- @mention team members
- Resolved/unresolved status

### Webhooks & API
- REST/GraphQL API for external access
- Webhooks for change notifications
- Integration with external tools

### Real-time Collaboration on Sheets
- Cursor sharing (like flows have now)
- Block locking
- Presence indicators

### Content Visibility & Secrets

> **Priority:** Low - User has alternative approach in mind

Inspired by World Anvil's secrets/visibility system, but adapted for game development:

**World Anvil's Approach:**
- Visibility toggles to hide parts of articles from viewers
- Secrets visible only to specific "subscriber groups"
- GMs can show different info to different players
- Spoiler markers for sensitive content

**Potential Use Cases for Storyarn:**
- Hide plot spoilers from QA testers
- Show different documentation to writers vs artists
- Restrict access to ending content during development
- "Work in progress" markers for incomplete sections

**Open Questions:**
- How does this relate to workspace/project roles?
- Per-block visibility or per-sheet?
- Does this belong in Storyarn or in external documentation tools?

**Note:** The user mentioned having a different approach in mind for visibility features. This section is kept as a reference for the World Anvil pattern, but implementation should follow the user's alternative design when specified.

---

## Assets — Enhancements

> **Dependency:** Assets Tool (implemented)
> **Priority:** Low — quality-of-life improvements
> **Related:** `docs/plans/ASSETS_IMPLEMENTATION_PLAN.md`

- Bulk upload
- Drag & drop reordering
- Asset folders/organization
- Asset versioning
- Waveform visualization for audio
- Duration metadata extraction
- Automatic transcription

---

*This document will be updated as features are designed and prioritized.*
