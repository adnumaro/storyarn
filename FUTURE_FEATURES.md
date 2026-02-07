# Future Features

> **Purpose:** Document planned features that are not in the current implementation scope
>
> **Last Updated:** February 6, 2026

---

## Variable State Timeline

> **Dependency:** Requires Phase 7.5 (block variables) + flow scripting system

### Concept

A debugging/preview tool that answers: **"What is the state of this entity at this point in the story?"**

When blocks are marked as variables, they can be modified by flow nodes (instructions). The timeline shows how variable values evolve as the player progresses through the narrative.

### Use Cases

1. **Designer Preview:** "If the player takes path A, what happens to Jaime's health?"
2. **Debugging:** "Why does this condition fail? What's the variable state here?"
3. **Documentation:** "Show me all the ways this character can change"

### Architecture

```
Variable Timeline System
├── Flow Scripting (prerequisite)
│   ├── Instruction nodes can modify variables
│   │   └── Syntax: #mc.jaime.health -= 30
│   ├── Condition nodes can read variables
│   │   └── Syntax: #mc.jaime.health > 50
│   └── Variables resolved at design-time for preview
│
├── State Calculation Engine
│   ├── Start from page's initial block values
│   ├── Walk through flow graph (or selected path)
│   ├── Apply variable modifications at each node
│   └── Track state at each step
│
├── Timeline Visualization
│   ├── Option A: On Page (References tab or new "Timeline" tab)
│   │   └── "This page's variables change in these flows at these nodes"
│   │
│   ├── Option B: On Flow (sidebar panel)
│   │   └── Select a node → see variable state at that point
│   │   └── Compare states between two nodes
│   │
│   └── Option C: Interactive Simulation
│       └── "Play" through the flow, making choices
│       └── See variable changes in real-time
│       └── Branch selection at hubs
│
└── Data Model
    flow_variable_changes (calculated, not stored)
    ├── flow_id
    ├── node_id
    ├── variable_path (#mc.jaime.health)
    ├── operation (set, add, subtract, etc.)
    └── expression (the instruction code)
```

### UI Concepts

#### Option A: Page Timeline Tab
```
┌─────────────────────────────────────────────────────────────┐
│ [Content] [References] [Timeline]                           │
├─────────────────────────────────────────────────────────────┤
│ VARIABLE CHANGES                                            │
│                                                             │
│ health (initial: 100)                                       │
│ ├─ 🔀 Chapter 1 / Node "Fight"    → 70  (-30)              │
│ ├─ 🔀 Chapter 1 / Node "Heal"     → 100 (+30)              │
│ └─ 🔀 Chapter 2 / Node "Ambush"   → 50  (-50)              │
│                                                             │
│ mood (initial: "neutral")                                   │
│ ├─ 🔀 Chapter 1 / Node "Victory"  → "happy"                │
│ └─ 🔀 Chapter 2 / Node "Betrayal" → "angry"                │
└─────────────────────────────────────────────────────────────┘
```

#### Option B: Flow State Inspector (sidebar)
```
┌──────────────────────────────────────┐
│ STATE AT: "Fight" node               │
├──────────────────────────────────────┤
│ #mc.jaime                            │
│   health: 70 (was 100)               │
│   mood: "neutral"                    │
│   is_alive: true                     │
│                                      │
│ #mc.elena                            │
│   trust_level: 5                     │
│   knows_secret: false                │
├──────────────────────────────────────┤
│ [Compare with another node ▼]        │
└──────────────────────────────────────┘
```

#### Option C: Interactive Simulation
```
┌─────────────────────────────────────────────────────────────┐
│ SIMULATION MODE                               [▶ Play] [⏹]  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Current Node: "Tavern Entrance"                             │
│                                                             │
│ 📍 State:                                                   │
│    #mc.jaime.health = 100                                   │
│    #mc.jaime.gold = 50                                      │
│                                                             │
│ 💬 "Welcome to the tavern, traveler."                       │
│                                                             │
│ Choose response:                                            │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ [1] "I need a room" → gold -= 10                         ││
│ │ [2] "I'm looking for someone" → (no change)              ││
│ │ [3] "Give me all your money!" → karma -= 20              ││
│ └──────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Implementation Phases

1. **Flow Scripting System** (prerequisite)
   - Define instruction syntax for variable modification
   - Define condition syntax for variable reading
   - Parser for expressions
   - Variable path resolution

2. **Basic State Calculation**
   - Walk linear flow paths
   - Apply modifications
   - Handle simple branches (show multiple outcomes)

3. **Timeline UI (Page)**
   - Show where variables change
   - Link to flow nodes

4. **State Inspector (Flow)**
   - Show state at selected node
   - Compare states

5. **Interactive Simulation** (advanced)
   - Playable preview
   - Choice selection
   - State tracking

### Complexity Considerations

- **Branching paths:** A flow can have many paths. Show all? Let user select?
- **Loops:** Flows might loop. How to handle infinite states?
- **Cross-flow jumps:** Variable changes might span multiple flows
- **Calculation performance:** Large flows with many variables could be slow
- **Conflicts:** Same variable modified differently in parallel branches

### Recommendation

Start with **Option B (Flow State Inspector)** as it's:
- Most immediately useful for debugging
- Scoped to single flow (simpler calculation)
- Doesn't require solving branching complexity initially

---

## Expression Text Mode (Power User Mode)

> **Dependency:** Requires Instruction Node (Phase A) shipped and tested
> **Priority:** P1 — first feature after visual builder ships

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

After the visual builder (Phase A) has shipped and received user feedback. If users with programming backgrounds report the builder as slow for bulk operations, this becomes high priority.

### Implementation Sketch

- Toggle button on the instruction panel: "Visual" / "Expression"
- Expression mode: single textarea with autocomplete (like articy:expresso)
- Autocomplete triggers on typing page shortcuts or variable names
- Syntax highlighting: page shortcuts in blue, variable names in green, operators in orange
- On save, parse the expression into the same `assignments` data structure
- Both modes read/write the same underlying data — switching is lossless

### Competitive Reference

articy:draft's expresso language (C#-like syntax with autocomplete and syntax highlighting). Dialogue System for Unity's Lua editor with wizard-generated code.

---

## Slash Commands in Value Input

> **Dependency:** Requires Instruction Node (Phase A)
> **Priority:** P3 — only if user demand emerges

### Concept

Typing `/page` in a value input field switches it to a page variable selector. Typing `/value` switches back to literal value input.

### Example Flow

1. User is in a value input field (expects a number)
2. Types `/page` → field transforms into a page+variable combobox
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

> **Dependency:** Requires Instruction Node (Phase A) + Condition Builder
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

| Tool | Approach | Visual Builder? | Non-Programmer Friendly? |
|---|---|---|---|
| **articy:draft** | C#-like text with autocomplete | No | Medium — C# syntax is barrier |
| **Twine (Harlowe)** | Functional macros `(set: $v to x)` | No | Easy for basics, steep for logic |
| **Ink (Inkle)** | Custom syntax (`~ x = 2`) | No | Writer-friendly but still code |
| **Yarn Spinner** | Tag-based `<<set $v to x>>` | No | Screenplay-like, accessible |
| **Chat Mapper** | Lua + dropdowns | Partial | Lua quirks frustrate users |
| **Dialogue System Unity** | Lua + **full dropdown wizard** | **Yes** | **Most accessible** for complex logic |
| **Fungus** | 100% visual blocks | **Yes** | Most accessible but tedious at scale |

### Key Findings

1. **No standalone narrative design tool** has a first-class visual instruction builder. Dialogue System for Unity has the closest equivalent, but it's a Unity plugin.

2. **The #1 pain point** across all tools is **remembering variable names**. Tools with autocomplete/dropdowns win.

3. **Visual builders become tedious at scale** (Fungus). Keyboard-driven flow mitigates this.

4. **Text editors exclude non-programmers** (articy, Ink). Sentence-flow UI bridges the gap.

5. **Writers prefer inline variable syntax** over separate GUI panels.

6. **Academic finding:** A Journal of Creative Technologies study found providing **multiple representations** (visual AND text) is the winning approach.

### Storyarn's Position

Storyarn occupies an **unserved niche**: a standalone narrative design tool with a visual instruction builder that feels like writing.

| Segment | Competition | Storyarn Advantage |
|---|---|---|
| Text scripting | articy, Ink, Yarn Spinner | Accessible to non-programmers |
| Pure visual blocks | Fungus | Scales better, less tedious |
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
│   ├── Collect page blocks as context
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
Page: Jaime (Character)
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

| Preset | Description | Best For |
|--------|-------------|----------|
| Fantasy Portrait | Detailed character art | Characters |
| Environment Concept | Wide landscape/interior | Locations |
| Item Render | Clean object on neutral BG | Items |
| Pixel Art | Retro game style | Retro games |
| Anime | Anime/manga style | Visual novels |
| Realistic | Photo-realistic | Modern settings |
| Sketch | Concept sketch style | Early development |

### Configuration Options

```elixir
%{
  label: "Character Portraits",
  style_preset: "fantasy_portrait",
  aspect_ratio: "1:1",        # 1:1, 16:9, 9:16, 4:3
  max_images: 12,
  auto_context: true,         # Use page blocks as context
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
   - Collect page blocks
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

## Page Templates

> **Status:** Discussed but deferred - revisit after Phase 7.5

### Concept

Reusable page structures with predefined blocks. Create a "Character" template, then create characters from it.

### Briefly Discussed

- Templates would define which blocks a page type has
- Similar to articy:draft's template system
- Could include default values
- Possibly inheritable/extendable

### Open Questions

- How do templates relate to shortcuts?
- Can a page's template be changed after creation?
- How to handle template updates (sync to existing pages?)
- Versioning for templates?

*To be fully designed when the feature is prioritized.*

---

## Features System (Reusable Property Groups)

> **Status:** Research needed - Study articy:draft's Feature system
>
> **Priority:** Medium - Would enhance Page Templates significantly

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

**Option B: Features as Page Types**
```
Features are special pages that define blocks:
- Page "/features/combat-stats" with blocks [health, attack, defense]

Templates inherit from multiple feature pages (multiple inheritance)
```

**Option C: Tags + Smart Defaults**
```
Instead of formal Features, use tags and smart defaults:
- Tag a page as "combatant" → suggest combat blocks
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

*This feature significantly impacts Page Templates. Should be researched before finalizing template design.*

---

## Technical Considerations

### Shortcut Auto-Update vs Page Versioning

> **Status:** Needs evaluation before implementing versioning (Phase 7.5.5)

**Current Behavior:**
- When a page/flow is renamed, its shortcut auto-updates to match the new name
- References are stored by ID (stable), so the actual shortcut text change is transparent
- When rendering a reference, the current shortcut is resolved from the ID

**Versioning Impact:**
When page versioning is implemented, consider how shortcut changes should be recorded:

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
   - Example: Version 1 had shortcut "hero", current page "hero-2" exists

**Recommendation:**
Evaluate these scenarios before implementing versioning. The simplest approach may be:
- Store shortcut in version snapshot (for record)
- On restore, regenerate shortcut from name (avoid conflicts)
- References always resolve to current state (simpler UX)

---

## Dialogue Node Enhancements (Deferred)

> **Related:** See DIALOGUE_NODE_ENHANCEMENT.md for current implementation plan

### Configurable Node Header Style

**Context:** When a speaker is selected for a dialogue node, the node header displays the speaker's avatar and name. Currently, the header keeps the default dialogue node color.

**Feature Request:** Enhance header customization with options:
- **Default mode** (current): Keep dialogue node color, show avatar + name
- **Banner mode**: Use `Page.banner_asset_id` as header background
- **Color mode**: Use speaker's custom color (requires adding color field to Page)

**Implementation Options:**

1. **Per-Page Setting:**
   ```elixir
   # Add to pages table
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
- Page settings: "Header display: [Default ▼] / [Banner ▼] / [Color ▼]"
- Dialogue node (optional): "Override header: [Use page default ▼]"

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

## Other Ideas (Not Yet Planned)

### Search & Query System
- Full-text search across pages and blocks
- Advanced query language (like articy)
- Saved searches/filters

### Rollups & Aggregations
- Sum/count/average of numeric blocks across pages
- "Total gold across all characters"
- Dashboard views

### Comments & Annotations
- Comments on pages/blocks
- @mention team members
- Resolved/unresolved status

### Webhooks & API
- REST/GraphQL API for external access
- Webhooks for change notifications
- Integration with external tools

### Real-time Collaboration on Pages
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
- Per-block visibility or per-page?
- Does this belong in Storyarn or in external documentation tools?

**Note:** The user mentioned having a different approach in mind for visibility features. This section is kept as a reference for the World Anvil pattern, but implementation should follow the user's alternative design when specified.

---

*This document will be updated as features are designed and prioritized.*
