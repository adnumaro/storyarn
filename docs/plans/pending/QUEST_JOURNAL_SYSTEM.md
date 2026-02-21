# Quest & Journal System

> **Goal:** Enable professional quest design workflows in Storyarn — journal entries, quest state tracking, and visual quest management — matching and improving on articy:draft's approach.
>
> **Motivation:** Games like Planescape: Torment have 1,800+ journal entries triggered from dialogue transitions. Quest/journal design is core narrative design work that belongs in the narrative tool, not in the game engine.
>
> **Status:** Draft — needs detailed design discussion
>
> **Last Updated:** February 20, 2026

---

## Competitive Analysis: articy:draft

### Key finding: No native quest system

articy:draft does **not** have a first-class quest system. Quests are emergent from combining generic building blocks:

- **Flow Fragments** serve as quest containers (nested flowcharts for hierarchy)
- **Templates** (Properties → Features → Templates) add typed metadata to any object
- **Global Variables** (organized in Variable Sets) track quest state at runtime
- **Conditions/Instructions on pins** gate and update quest state
- **Nesting** (submerge/emerge) provides act → quest → stage → objective hierarchy

### How quest state works in articy

Quest progression uses **integer variables** as state machines:

| Value | State |
|:---:|:---|
| 0 | Locked / Unavailable |
| 1 | Available |
| 2 | Active |
| 3 | Completed |
| 4 | Failed |

Instructions on output pins advance state: `Quests.DragonHunt = 2;`
Conditions on input pins gate content: `Quests.DragonHunt == 2`

### How journal entries work in articy

Journal text is **not** a built-in feature. It's handled through:
- Template text properties on quest Flow Fragments (description, success text)
- Global variable changes that the game engine interprets as journal updates
- No in-tool journal preview or quest log view

### What articy does well

- Template system for visual differentiation (quest nodes get custom icons + colors)
- Nesting for natural hierarchy (act → quest → stage → objective)
- Simulation mode evaluates conditions/instructions live with variable tracking
- Variable rename propagates across all scripts

### What articy does poorly

- No dedicated journal/quest log — designers must imagine how text maps to the in-game journal
- No quest overview dashboard — must navigate the flow tree manually
- Runtime flow traversal too limited for actual quest management (SpellForce 3 team abandoned it)
- No "where is this quest referenced?" cross-reference view
- Quest state is just integers — no visual indicator of quest progress in the editor

---

## What Storyarn Already Has (Equivalent Features)

| articy Concept | Storyarn Equivalent | Status |
|----------------|---------------------|--------|
| Flow Fragments | Flows | ✅ |
| Templates on objects | Sheets (with inheritance) | ✅ |
| Global Variables | Sheet blocks (variables) | ✅ |
| Variable Sets (namespaces) | Sheets (one sheet = one namespace) | ✅ |
| Condition nodes | Condition nodes (normal + switch mode) | ✅ |
| Instruction nodes | Instruction nodes | ✅ |
| Nesting / submerge | Subflow nodes + flow tree hierarchy | ✅ |
| Conditions on pins | Response conditions | ✅ |
| Instructions on pins | Response instructions (Gap 5, pending) | 🔄 |
| Simulation mode | Story Player + Debugger | ✅ |
| Jump nodes | Jump → Hub nodes | ✅ |
| Template icons/colors | Node type icons (fixed per type) | ⚠️ Partial |
| Pin script indicators | Response condition indicator `[?]` | ⚠️ Partial |

**Storyarn can model quests today** using flows + sheets + variables + conditions/instructions. What's missing is quest-specific UX.

---

## What's Missing — Proposed Features

### 1. Journal Entries on Responses

**The core missing feature.** When a player selects a dialogue response, a journal entry can be triggered alongside the instruction.

**Data model — add `journal` field to responses:**

```elixir
# Current response structure
%{
  "id" => "resp_1",
  "text" => "I'll find the Bronze Sphere",
  "condition" => %{...},
  "instruction" => nil         # becoming assignments[] via Gap 5
}

# Proposed addition
%{
  "id" => "resp_1",
  "text" => "I'll find the Bronze Sphere",
  "condition" => %{...},
  "instruction" => %{...},     # assignments[] via Gap 5
  "journal" => %{              # NEW
    "text" => "Pharod asked me to find the Bronze Sphere in the catacombs",
    "quest_ref" => "quest_pharod_sphere",   # optional: links to a quest flow/sheet
    "type" => "update"                       # "start" | "update" | "complete" | "fail"
  }
}
```

**UI in the full editor (Gap 4):**

Each response card gains an optional journal section (collapsible, similar to condition/instruction):

```
┌──────────────────────────────────────┐
│ 1. "I'll find the Bronze Sphere"  ✕ │
│                                      │
│ ▸ Condition  [Builder|Code]          │
│ ▸ Instruction  [Builder|Code]        │
│ ▸ Journal  [📖 update]              │
│   "Pharod asked me to find the       │
│    Bronze Sphere in the catacombs"   │
└──────────────────────────────────────┘
```

**In the Story Player / Debugger:**

When a response with a journal entry is selected, the debugger console shows:
```
📖 Journal [update]: "Pharod asked me to find the Bronze Sphere..."
```

A dedicated "Journal" tab in the debug panel shows accumulated entries in chronological order — a live quest log preview.

**Files affected:**
- `lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex` — journal field in response data
- `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` — journal UI in response cards
- `lib/storyarn/flows/evaluator/node_evaluators/dialogue_node_evaluator.ex` — process journal on response selection
- `lib/storyarn/flows/evaluator/state.ex` — add `journal_entries` list to debug state
- Debug panel — new "Journal" tab

### 2. Journal Entries on Instruction Nodes

Standalone instruction nodes can also trigger journal entries (useful when multiple paths converge to the same quest state change).

**Data model — add optional `journal` field to instruction node data:**

```elixir
%{
  "description" => "Complete Pharod's quest",
  "assignments" => [...],
  "journal" => %{
    "text" => "I returned the Bronze Sphere to Pharod",
    "quest_ref" => "quest_pharod_sphere",
    "type" => "complete"
  }
}
```

**Files affected:**
- `lib/storyarn_web/live/flow_live/nodes/instruction/node.ex` — journal field
- `lib/storyarn_web/live/flow_live/nodes/instruction/config_sidebar.ex` — journal UI
- `lib/storyarn/flows/evaluator/node_evaluators/instruction_evaluator.ex` — process journal

### 3. Quest Flow Designation (Lightweight)

Instead of a heavy template system, a lightweight approach: flows can be **tagged as quest flows** with minimal metadata.

**Data model — extend flow metadata:**

```elixir
# In flow data or a dedicated quest_metadata JSONB field
%{
  "quest" => %{
    "enabled" => true,
    "state_variable" => "quests.dragon_hunt",   # links to a sheet variable
    "type" => "side",                             # "main" | "side" | "task"
    "description" => "Find and slay the dragon threatening the village"
  }
}
```

**Visual differentiation:**
- Quest flows get a badge/icon in the flow tree sidebar (e.g., `⚔` for main, `◇` for side)
- Quest flows with a linked state variable show the current state in the tree (if debugging)

**This is intentionally minimal.** articy's template system is powerful but complex. Storyarn's sheets + inheritance already provide the template functionality. Quest designation is just a **tag + variable link** for visual/organizational purposes.

### 4. Quest Overview (Future)

A dashboard view showing all quest flows in the project with:
- Quest name, type, linked state variable
- Current state (if in debug/player mode)
- Journal entries collected so far
- Cross-references (which flows reference this quest's variables)

This builds on Gap 6c (Variable Usage Index) — if we know which flows read/write `quests.dragon_hunt`, we know the quest's touchpoints.

**This is a future feature**, not needed for the stress test or initial implementation.

---

## Comparison: articy vs Proposed Storyarn

| Capability | articy:draft | Storyarn (proposed) | Improvement |
|------------|-------------|---------------------|-------------|
| Quest containers | Flow Fragments + Templates | Flows + quest tag | Simpler, less overhead |
| Quest state | Integer global variables | Sheet variables (already typed) | Same |
| Journal entries | Not built-in (template text only) | **First-class on responses + instructions** | **Major improvement** |
| Journal preview | None | **Live journal tab in debugger** | **Major improvement** |
| Quest hierarchy | Nesting (submerge/emerge) | Flow tree + subflows | Same |
| Quest overview | None (navigate tree manually) | Planned dashboard (future) | Improvement |
| Visual markers | Template icons + colors | Quest badges in flow tree | Similar |
| Cross-references | Manual search | Variable usage index (Gap 6c) | Improvement |

**Storyarn's key advantage:** Journal entries as a first-class feature with live preview in the debugger. articy treats journal text as an afterthought (just template properties), forcing designers to imagine how their text maps to the in-game journal. Storyarn can show them.

---

## Implementation Approach

### For the Stress Test (COMPLEX_NARRATIVE_STRESS_TEST.md)

Torment's 1,800+ journal entries are stored in the extracted data as `transition.journal`. During import:
- Store journal text as the `journal.text` field on the corresponding response
- Set `journal.type` based on heuristics (first mention = "start", variable increment = "update", quest variable set to max = "complete")
- The debugger's journal tab shows entries as they accumulate during playthrough

### Phased Implementation

**Phase 1: Journal entries (core value)**
- Journal field on responses (data model + UI in full editor)
- Journal field on instruction nodes
- Journal tab in debugger/Story Player
- Effort: Medium

**Phase 2: Quest flow designation**
- Quest tag + metadata on flows
- Visual badges in flow tree
- Effort: Low

**Phase 3: Quest overview dashboard (future)**
- Dedicated view aggregating all quest flows
- Cross-reference integration with variable usage index
- Effort: Medium

---

## Open Questions

1. **Journal entry localization:** Should journal text go through the same i18n system as dialogue text? Probably yes, but adds complexity.

2. **Quest state variable link:** Should the quest flow "know" which variable tracks its state, or is this just a convention? A formal link enables the quest overview dashboard but adds coupling.

3. **Journal entry types:** Is `start | update | complete | fail` sufficient, or do we need custom types?

4. **Multiple journal entries per response:** Can one response trigger multiple journal entries (e.g., complete quest A + start quest B)? Probably yes — make `journal` an array.

5. **Journal entries outside dialogue:** Should condition nodes also be able to trigger journal entries (e.g., "you entered the forbidden zone")? Or only responses and instructions?
