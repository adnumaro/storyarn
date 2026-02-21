# Complex Narrative Stress Test — Scaling Storyarn for AAA Complexity

> **Goal:** Identify and resolve all gaps that prevent Storyarn from handling narratives with the complexity of Planescape: Torment (806 characters, 15,918 dialogue states, 45,460 branching transitions, 1,056 variables)
>
> **Benchmark:** Full importability of Planescape: Torment's dialogue system as a stress test
>
> **Approach:** Fix platform gaps first, then build an import script to validate
>
> **Last Updated:** February 20, 2026

---

## Context

We extracted the complete dialogue system from Planescape: Torment:

| Metric                                       | Value   |
|----------------------------------------------|---------|
| Dialogue files (NPCs/conversations)          | 806     |
| States (NPC lines / dialogue nodes)          | 15,918  |
| Transitions (player choices + links)         | 45,460  |
| Unique game variables                        | 1,056   |
| Conditions (branching logic)                 | 15,480  |
| Actions (variable mutations)                 | 9,461   |
| Game areas                                   | 33      |
| Max states in a single dialogue (Morte)      | 743     |
| Max transitions from a single state          | 34      |
| Max cross-references to a single NPC (Morte) | 122     |

This data is in `docs/game_references/planescape_torment/dialogs/`.

---

## Gap Analysis

### Gap 1: Nested Conditions (CRITICAL)

**Problem:** Storyarn conditions are a flat list of rules with a single logic operator (`all` or `any`). Torment requires AND-within-OR and OR-within-AND:

```
# Torment pattern — cannot be expressed today
IF (InParty("Annah") AND Global("Annah", 0))
   OR (GlobalGT("Know_Annah", 2))
```

**Current structure:**
```json
{"logic": "all", "rules": [rule1, rule2, rule3]}
```

**Impact:** 15,480 conditions. Simple ones (single variable check) work fine. Compound ones with mixed AND/OR need workaround chains of multiple condition nodes, which is verbose and hard to read.

#### Design: Block-based conditions with grouping

The condition builder evolves from a flat rule list into a **block-based** system with 3 hierarchy levels:

**Level 1 — Top level:** A list of blocks/groups with a single AND/OR toggle that applies to all items at this level.

**Level 2 — Block:** A set of rules (leaf conditions) with its own AND/OR toggle. This is what the current builder already is. Each block is a visual card.

**Level 3 — Group:** A set of blocks wrapped together. Created by user via bulk-selection. Has its own AND/OR toggle between its inner blocks. Visually wrapped with a colored border.

##### Normal mode UI:

```
[ALL ▾] of these blocks:
┌────────────────────────────────────────────────┐
│  [ALL ▾] of these rules:                       │
│  global · annah  equals  0                   ✕ │
│  party · annah_present  is true              ✕ │
│  [+ Add rule]                                  │
└────────────────────────────────────────────────┘
┌────────────────────────────────────────────────┐
│  global · know_annah  greater than  2        ✕ │
│  [+ Add rule]                                  │
└────────────────────────────────────────────────┘
┌────────────────────────────────────────────────┐
│  global · fortress  equals  3                ✕ │
│  [+ Add rule]                                  │
└────────────────────────────────────────────────┘

[+ Add block]  [Group]
```

The AND/OR toggle between blocks is a single toggle at the top of the condition — it applies globally to all items at that level.

Within each block, the AND/OR toggle for rules only appears when the block has 2+ rules (same as current behavior).

##### Grouping interaction:

1. User clicks **[Group]** button → enters selection mode
2. All blocks become non-editable, checkboxes appear on the left of each block
3. User checks 2+ blocks → **[Group selected (N)]** button activates
4. Clicking it wraps the selected blocks in a group
5. **[Cancel]** exits selection mode without changes

```
Selection mode:

☐ ┌──────────────────────────────────────────┐
   │  global · annah  equals  0               │  (dimmed)
   │  party · annah_present  is true          │
   └──────────────────────────────────────────┘
☑ ┌──────────────────────────────────────────┐
   │  global · know_annah  greater than  2    │  (selected)
   └──────────────────────────────────────────┘
☑ ┌──────────────────────────────────────────┐
   │  global · fortress  equals  3            │  (selected)
   └──────────────────────────────────────────┘

[Cancel]  [Group selected (2)]
```

##### After grouping:

```
[ALL ▾] of these blocks:
┌────────────────────────────────────────────────┐
│  [ALL ▾] of these rules:                       │
│  global · annah  equals  0                   ✕ │
│  party · annah_present  is true              ✕ │
│  [+ Add rule]                                  │
└────────────────────────────────────────────────┘
┌─ Group ───────────────────────────────────────────┐
│  [AND ▾] of these blocks:                         │
│  ┌────────────────────────────────────────────┐   │
│  │  global · know_annah  greater than  2    ✕ │   │
│  │  [+ Add rule]                              │   │
│  └────────────────────────────────────────────┘   │
│  ┌────────────────────────────────────────────┐   │
│  │  global · fortress  equals  3            ✕ │   │
│  │  [+ Add rule]                              │   │
│  └────────────────────────────────────────────┘   │
│  [+ Add block]                         [Ungroup]  │
└───────────────────────────────────────────────────┘

[+ Add block]  [Group]
```

Groups have:
- A colored left border to differentiate from regular blocks
- Their own AND/OR toggle (global within the group)
- An [Ungroup] button to dissolve back into separate blocks
- Ability to add blocks inside the group
- Max nesting: 1 level of groups (no groups within groups)

##### Backwards compatibility

A condition with a single block containing flat rules is equivalent to the current format. The migration path:

- **Current format:** `{"logic": "all", "rules": [rule1, rule2]}` — still valid, treated as a single block
- **New format:** `{"logic": "any", "blocks": [{"logic": "all", "rules": [...]}, ...]}`
- Old format is auto-upgraded to new format on first edit (wrap rules in a single block)
- `condition.ex` accepts both formats

##### Data model

```json
{
  "logic": "all",
  "blocks": [
    {
      "id": "block_1",
      "type": "block",
      "logic": "all",
      "rules": [
        {"id": "rule_1", "sheet": "global", "variable": "annah", "operator": "equals", "value": "0"},
        {"id": "rule_2", "sheet": "party", "variable": "annah_present", "operator": "is_true"}
      ]
    },
    {
      "id": "group_1",
      "type": "group",
      "logic": "and",
      "blocks": [
        {
          "id": "block_2",
          "type": "block",
          "logic": "all",
          "rules": [{"id": "rule_3", "sheet": "global", "variable": "know_annah", "operator": "greater_than", "value": "2"}]
        },
        {
          "id": "block_3",
          "type": "block",
          "logic": "all",
          "rules": [{"id": "rule_4", "sheet": "global", "variable": "fortress", "operator": "equals", "value": "3"}]
        }
      ]
    }
  ]
}
```

Type discrimination: `"type": "block"` has `rules` (leaf rules), `"type": "group"` has `blocks` (nested blocks). Max depth: top → group → block → rule (3 levels). Groups cannot contain other groups.

**Files affected:**
- `lib/storyarn/flows/condition.ex` — new format parsing, validation, sanitization, backwards compat
- `lib/storyarn/flows/engine/condition_eval.ex` — recursive evaluation (block → group → block → rules)
- `assets/js/screenplay/builders/condition_builder_core.js` — block rendering, group selection mode, grouping/ungrouping
- `assets/js/condition_builder/condition_rule_row.js` — no changes (still renders leaf rules)
- New: `assets/js/condition_builder/condition_block.js` — renders a block card (rules + add rule + AND/OR toggle)
- New: `assets/js/condition_builder/condition_group.js` — renders a group wrapper (blocks + add block + ungroup)
- `assets/js/hooks/condition_builder.js` — pass through new format
- `lib/storyarn_web/components/condition_builder.ex` — pass through new format
- Condition node sidebar — no changes (delegates to builder component)

**Effort:** Medium-High. Backend recursive eval is straightforward. The JS builder needs significant rework: block cards, selection mode, grouping gesture, group rendering. The combobox/rule-row code stays the same.

---

### Gap 2: Canvas Performance at Scale (MEDIUM)

**Problem:** A flow with 743 dialogue nodes + auxiliary condition/instruction nodes (~1,500+ total) may be hard to navigate visually and slow to interact with at full detail.

**Already implemented:**

- **LOD / Semantic zoom** — ✅ Two tiers: `"full"` (per-type render) and `"simplified"` (generic header + bare sockets). Hysteresis band at zoom 0.40–0.45. Batched DOM updates (50 nodes per rAF frame). See `lod_controller.js`, `storyarn_node.js`.
- **Minimap** — ✅ `rete-minimap-plugin` integrated, size 200px, deferred registration after bulk load. See `setup.js`, `flow_canvas.js`.
- **Optimized bulk loading** — ✅ `_deferSocketCalc` skips per-node events during initial load. Nodes start in simplified LOD during load, transition to full after `zoomAt`.

**Remaining gap: Auto-layout**

Large flows (especially imported ones) need automatic layout. Currently all flows depend on manual positioning. An auto-layout algorithm would arrange nodes in a readable tree/graph structure.

Use cases:
- Import script: 806 flows with no position data need automatic arrangement
- User action: "Re-layout" button to reorganize a messy flow
- Could also offer layout presets (top-to-bottom tree, left-to-right, force-directed)

**Proposed solution:**

Integrate a JS graph layout library (Dagre for tree-like DAGs, or ELK for more complex graphs). Expose as:
1. A function callable from the import script (position nodes before persisting)
2. A user-triggered action in the flow toolbar ("Auto-layout" button)

**Files affected:**
- New: `assets/js/flow_canvas/auto_layout.js` — Dagre/ELK integration
- `assets/js/hooks/flow_canvas.js` — "Auto-layout" toolbar action + pushEvent to persist positions
- Server handler to batch-update node positions after layout

**Effort:** Medium.

**Import strategy note:** For dialogues with 200+ states, the import script should also consider splitting into sub-flows using the Subflow node (one per narrative phase/entry point). This keeps individual canvases manageable while preserving the full tree. This is an import-time decision, not a platform change.

---

### Gap 3: Conditional Entry Points Pattern — RESOLVED + QoL improvement

**Problem:** In Torment, when you talk to an NPC, the engine checks states top-to-bottom and the **first state whose condition matches** is the conversation entry point. Annah has 186 entry points.

**Resolution: Already solvable via componentization + existing features.**

The pattern is handled by splitting each NPC's dialogue into a **router flow** + **phase sub-flows**:

```
📁 Annah/
├── Router (flow)
│   Entry → Condition (switch mode, first match wins)
│           ──"Phase 0: First meeting"──→ Exit (→ Annah Phase 0)
│           ──"Phase 1: Recruited"─────→ Exit (→ Annah Phase 1)
│           ──"Phase 2: In party"──────→ Exit (→ Annah Phase 2)
│           ──"Phase 3: Fortress"──────→ Exit (→ Annah Phase 3)
│           ──"default"────────────────→ Exit (→ Annah Default)
│
├── Phase 0 - First meeting (flow)     ← small, manageable
├── Phase 1 - Recruited (flow)
├── Phase 2 - In party (flow)
└── Phase 3 - Fortress (flow)
```

Everything needed already works:

- **Condition switch mode** evaluates rules in order, first match wins (`condition_node_evaluator.ex:64-75`)
- **Default pin** already functional — engine falls back to `"default"` when no case matches (`condition_node_evaluator.ex:73,108-109`), canvas renders it as last output (`condition.js:137`)
- **Exit → flow reference** already connects flows together
- **Subflow nodes** already support calling another flow and returning
- **Flow tree hierarchy** already supports folder-like organization

**Only dependency:** Gap 1 (nested conditions) — so each switch rule can express complex conditions like `Annah == 0 AND Know_Annah < 2 AND NOT InParty(Annah)` instead of just a single variable check.

#### QoL: "Create linked flow" from exit/subflow nodes

Creating the router → sub-flow pattern today requires 6 steps (create flow separately, go back, assign it). This should be 1 click.

**Feature: "Create linked flow"** available on both exit nodes and subflow nodes:

- **Trigger:** Context menu (right-click) on exit/subflow node → "Create linked flow", or button in sidebar when no flow is assigned
- **Behavior:**
  1. Creates a new flow as a child of the current flow in the tree
  2. **Name:** inherits from the node's label (exit label or subflow reference name). Fallback: parent flow name + incremental suffix
  3. Assigns the new flow to the node automatically (sets `referenced_flow_id`)
  4. Redirects the user to the new flow

**Files affected:**
- `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` — new `"create_linked_flow"` event handler
- `lib/storyarn_web/live/flow_live/nodes/exit/config_sidebar.ex` — "Create new flow" button when no flow assigned
- `lib/storyarn_web/live/flow_live/nodes/subflow/config_sidebar.ex` — same button
- `assets/js/flow_canvas/handlers/` — context menu entry for exit/subflow nodes
- `lib/storyarn/flows/flow_crud.ex` — create child flow + assign to node in one transaction

**Effort:** Low-Medium.

---

### Gap 4: Dialogue Node UX — Floating Toolbar + Full Editor (HIGH)

**Problem:** The dialogue node sidebar (320px) crams too much content into a single scrollable column: speaker, stage directions, Tiptap rich text editor, responses (each with condition builder + instruction field), menu text, audio picker, and technical IDs. As we add nested conditions (Gap 1) and response instructions (Gap 5), the sidebar becomes unusable.

**Current state:** Single click opens a scrollable right sidebar. Double-click opens the Screenplay editor (fullscreen overlay, but only handles speaker + stage directions + text — responses are read-only with "Edit responses in the sidebar panel").

#### Solution: Two-level editing

**Level 1 — Floating Toolbar** (on node selection):

A floating toolbar appears above the selected dialogue node (same pattern as map elements in `floating_toolbar.js`):

```
[Speaker ▾] | [🔊] [3 responses] | [✏ Edit] [▶]
```

- **Speaker dropdown** — quick speaker change without opening any panel
- **Audio indicator** — shows whether audio is attached
- **Response count** — informational badge (not editable here)
- **Edit button** — opens the full editor (primary action)
- **Preview button** — starts Story Player preview from this node

The toolbar follows the node on pan/zoom, hides during drag, repositions on release. Reuses the same JS positioning module as the map floating toolbar.

**Level 2 — Full Editor** (deep editing):

Triggered by: **double-click** on node, **Shift+click**, or **Edit button** in toolbar.

Fullscreen overlay (evolution of the existing Screenplay editor) with two-column layout:

```
┌──────────────────────────────────────────────────────────────────┐
│  [← Back to canvas]                             [Settings ⚙] [✕]│
├──────────────────────────────┬───────────────────────────────────┤
│                              │                                   │
│  ANNAH                       │  Responses                        │
│  (whispering)                │  ┌──────────────────────────────┐ │
│                              │  │ 1. "Tell me about the Hive"  │ │
│  You see a striking          │  │    Condition: [builder]      │ │
│  red-haired girl leaning     │  │    Instruction: [builder]    │ │
│  against a wall...           │  └──────────────────────────────┘ │
│                              │  ┌──────────────────────────────┐ │
│                              │  │ 2. "Who are you?"            │ │
│                              │  │    Condition: [builder]      │ │
│                              │  └──────────────────────────────┘ │
│                              │  [+ Add response]                 │
│                              │                                   │
├──────────────────────────────┴───────────────────────────────────┤
│  🔊 Audio: scene_01.wav  │  Words: 142  │  ID: dlg_annah_01    │
└──────────────────────────────────────────────────────────────────┘
```

- **Left column:** Speaker selector, stage directions, Tiptap text editor (generous width for writing)
- **Right column:** Full response list — each response card includes text, condition builder, and instruction builder (Gap 5). Scrollable for many responses.
- **Footer bar:** Audio, word count, technical/localization IDs (compact, rarely accessed)
- **Settings gear:** Popover for secondary fields (menu text, etc.)

This replaces the current Screenplay editor. Same entry points, but now a complete node editor instead of text-only.

#### Delete behavior (all node types)

- **Delete/Backspace key** with a selected node → deletes immediately, no confirmation dialog
- **Undo (Ctrl+Z / Cmd+Z)** restores the node (already implemented via `DeleteNodeAction` + `restore_node`)
- Delete button removed from sidebar footer for all node types
- Confirm modal for delete (`delete-node-confirm`) removed from `properties_panels.ex`
- Organic UX: zero friction dialogs anywhere

#### Also resolves: former Gap 7 (Many Responses UI)

The original concern about 34 responses in a 320px sidebar accordion is eliminated: the full editor's right column provides ample space for scrollable response lists with condition and instruction builders per response.

**Files affected:**

*Floating Toolbar:*
- New: `lib/storyarn_web/live/flow_live/components/dialogue_toolbar.ex` — floating toolbar HEEx component
- New: `assets/js/flow_canvas/floating_toolbar.js` — JS positioning module (reuse pattern from `map_canvas/floating_toolbar.js`)
- `assets/js/hooks/flow_canvas.js` — show/hide toolbar on selection, reposition on pan/zoom/drag
- `lib/storyarn_web/live/flow_live/show.ex` — toolbar container div, event wiring

*Full Editor (evolve Screenplay):*
- `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` — major rework: two-column layout, response editing with condition + instruction builders
- `lib/storyarn_web/live/flow_live/nodes/dialogue/config_sidebar.ex` — removed or reduced to minimal fallback
- `assets/js/hooks/dialogue_screenplay_editor.js` — updated for new layout

*Delete cleanup (all node types):*
- `lib/storyarn_web/live/flow_live/components/properties_panels.ex` — remove delete button and confirm modal from footer
- `assets/js/flow_canvas/handlers/keyboard_handler.js` — no changes needed (already deletes without confirmation)

**Effort:** High. The floating toolbar is medium (reuse maps positioning pattern). The full editor is the bulk — evolving Screenplay from text-only to complete node editor with response management, condition builders, and instruction builders.

---

### Gap 5: Expression System — Code Editor + Visual Builder (HIGH)

**Problem:** The `responses[].instruction` field is deprecated and non-functional. In Torment, 9,461 transitions have actions (variable assignments on response selection). Beyond responses, the condition and instruction systems need a professional expression editing experience to handle complex narratives at scale.

**Current state:** Conditions and instructions are edited exclusively via the visual builder (sentence-flow comboboxes). There is no text-based expression editor. The response `instruction` field is a dead string input with no backend logic.

#### Solution: Dual-mode expression editor

A tabbed editor that provides two synchronized views of the same data:

- **Builder tab:** The existing visual builder (sentence-flow comboboxes) — intuitive for simple cases
- **Code tab:** A lightweight code editor with syntax highlighting, error markers, and variable autocomplete — efficient for complex expressions and power users

Both tabs share the same underlying structured data. Changes in one reflect in the other.

##### Expression DSL (inspired by articy:draft Expresso)

**Instructions (assignments):**
```
mc.jaime.health = 50
global.quest_progress += 1
mc.jaime.class = "warrior"
party.annah_present = true
```

**Conditions (boolean expressions):**
```
mc.jaime.health > 50
global.quest_progress >= 3 && party.annah_present
!(mc.jaime.dead) || global.override
mc.jaime.class == "warrior"
```

**Operators:**
- Assignment: `=` (set), `+=` (add), `-=` (subtract), `?=` (set if unset)
- Comparison: `==`, `!=`, `>`, `<`, `>=`, `<=`
- Logic: `&&` (AND), `||` (OR), `!` (NOT), parentheses for grouping
- Variables use existing Storyarn format: `sheet_shortcut.variable_name`

These operators map 1:1 to the existing Storyarn operator set (`set`, `add`, `subtract`, `equals`, `greater_than`, etc.).

##### Code editor: CodeMirror 6

Lightweight (~50-60KB gzipped), modular, extensible. Only import what's needed:
- `@codemirror/state` + `@codemirror/view` — core editor
- `@codemirror/language` + custom Lezer grammar — syntax highlighting for the expression DSL
- `@codemirror/autocomplete` — variable name completion from project variables
- `@codemirror/lint` — inline error markers (red underlines, hover messages)
- Custom theme to match Storyarn's design system

Monaco (~2-5MB) is overkill. Anything lighter than CodeMirror 6 would mean reinventing the wheel.

##### Architecture

```
Code text ←→ Lezer AST ←→ Structured data (assignments[] / condition{})
                                    ↕
                            Visual Builder
```

- **Lezer grammar** — formal definition of the expression DSL, generates the parser
- **Parser** — text → AST → structured JSON (the existing `assignments`/`condition` format)
- **Serializer** — structured JSON → human-readable text
- **Sync** — on tab switch, structured data is the shared source of truth. Builder → serialize → Code. Code → parse → Builder.

##### UI in the full editor (Gap 4)

Each response card with tabs for both condition and instruction:

```
┌──────────────────────────────────────┐
│ 1. "Tell me about the Hive"       ✕ │
│                                      │
│ ▸ Condition  [Builder|Code]          │
│   mc.jaime.health > 50 &&           │
│   global.quest >= 3                  │
│                                      │
│ ▸ Instruction  [Builder|Code]        │
│   global.know_annah = 3             │
│   global.quest_prog += 1            │
└──────────────────────────────────────┘
```

##### Applies everywhere

The dual-mode editor is used in ALL expression contexts:
- **Condition nodes** — condition builder gets Code tab
- **Instruction nodes** — instruction builder gets Code tab
- **Response conditions** — in full editor (Gap 4)
- **Response instructions** — in full editor (Gap 4)

##### Impact on Gap 1 (Nested Conditions)

The code editor provides a natural escape hatch for complex nested conditions. Instead of the block-based grouping UI, power users can type `(A && B) || (C && D)` directly. Both modes coexist: the visual builder handles the UI complexity of Gap 1, the code editor provides a fast alternative.

##### Scope

1. **Define DSL** — formal grammar for assignments + boolean expressions
2. **Lezer grammar + parser** — text → AST → structured data, with error recovery
3. **Serializer** — structured data → text (pretty-printed, readable)
4. **CodeMirror 6 component** — Phoenix hook wrapping the editor with highlighting, autocomplete, lint
5. **Tab switcher component** — Builder | Code, bidirectional sync via shared structured data
6. **Integrate in all contexts** — condition nodes, instruction nodes, response conditions, response instructions
7. **Response instruction backend** — replace dead `instruction` string field with `assignments` array, wire engine to execute on response selection

**Files affected:**

*Expression DSL:*
- New: `assets/js/expression_editor/grammar.js` — Lezer grammar definition
- New: `assets/js/expression_editor/parser.js` — AST → structured data transformer
- New: `assets/js/expression_editor/serializer.js` — structured data → text
- New: `assets/js/expression_editor/theme.js` — CodeMirror theme matching Storyarn

*Code Editor component:*
- New: `assets/js/hooks/expression_editor.js` — Phoenix hook wrapping CodeMirror 6
- New: `assets/js/expression_editor/autocomplete.js` — variable name completion from project variables
- New: `assets/js/expression_editor/linter.js` — validation + error markers

*Tab switcher:*
- New: `lib/storyarn_web/components/expression_editor.ex` — HEEx component with Builder|Code tabs
- `lib/storyarn_web/components/condition_builder.ex` — wrap in tab switcher
- `lib/storyarn_web/components/instruction_builder.ex` — wrap in tab switcher

*Response instructions backend:*
- `lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex` — `assignments` field replaces `instruction` string
- `lib/storyarn/flows/engine/node_evaluators/dialogue_node_evaluator.ex` — execute response assignments on selection
- `lib/storyarn/flows/instruction.ex` — shared validation for response assignments

*Integration in full editor (Gap 4):*
- `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` — expression editors in response cards

##### Variable autocomplete at scale

With 1,056 variables, the visual builder's combobox becomes unusable. Both editing modes need to handle this:

- **Code tab:** CodeMirror autocomplete with fuzzy search — naturally handles large variable lists (type a few characters, get filtered suggestions)
- **Builder tab:** The current combobox dropdown needs improvement — group variables by sheet in the dropdown, add inline search/filter. Without this, selecting from 1,000+ flat options is impractical.

This is not a separate gap but must be addressed during Gap 5 implementation.

**Effort:** High. New DSL grammar, parser, serializer, CodeMirror integration, tab sync, and backend wiring. The visual builders stay as-is — this adds the Code mode alongside them.

---

### Gap 6: Search and Navigation (MEDIUM)

**Problem:** With 806 flows, current search is insufficient:
- `search_flows` returns max **10 results**
- No filters (by tag, area, character type)
- No global "where is variable X used?" view
- No "what flows reference this flow?" beyond the Entry node sidebar

**Proposed solutions:**

#### 6a. Increase search limit + add pagination

Change `search_flows` and `search_sheets` to return 25+ results with scroll-to-load.

**Files affected:**
- `lib/storyarn/flows/flow_crud.ex` — increase limit, add offset
- Sidebar search component — infinite scroll or "show more"

#### 6b. Flow tags

Add a `tags` field (string array) to the Flow schema. Tags are freeform, project-scoped, autocompleted from existing tags.

Use cases for Torment: `area:mortuary`, `area:hive`, `companion`, `merchant`, `quest:main`.

**Files affected:**
- `lib/storyarn/flows/flow.ex` — add `tags` field (array of strings)
- Migration: add `tags` column
- Sidebar tree: filter by tag
- Flow settings modal: tag editor

#### 6c. Variable usage index

A view that shows, for each variable:
- Which flows READ it (conditions)
- Which flows WRITE it (instructions)

The `variable_references` table already tracks this! The gap is just a **UI to surface it**.

**Files affected:**
- New LiveView or modal: Variable usage browser
- Query `variable_references` grouped by block_id

#### 6d. Cross-flow navigation history

With 806 interconnected flows, users will constantly jump between flows via subflow/exit nodes. The editor needs navigation history (same pattern as map pin navigation).

- **Back/forward buttons** in the flow editor toolbar (browser-style history)
- **Breadcrumb trail** showing the navigation path (Flow A → Flow B → Flow C)
- Keyboard shortcuts: `Alt+←` / `Alt+→` for back/forward

The debugger's call stack already tracks this for debug sessions. The editor needs the same for manual navigation.

**Files affected:**
- `lib/storyarn_web/live/flow_live/show.ex` — navigation history stack in socket assigns
- Flow editor toolbar — back/forward buttons + breadcrumbs
- Subflow/exit node click handlers — push to history before navigating

**Effort:** Low-Medium per sub-item. Tags are the highest value. Cross-flow navigation is low effort (history stack + UI buttons).

---

### Gap 7: Instruction Operators — `set_if_unset` — ABSORBED by Gap 5

**Original problem:** Torment's `IncrementGlobalOnce` (1,675 uses) — increment a variable only if it hasn't been incremented before. Storyarn's `add` operator always increments.

**Resolution:** Absorbed into Gap 5 (Expression System) as a new operator `?=` ("set if unset"). Sets the value only if the current value is `nil` or the block's default. Maps 1:1 between code editor (`global.var ?= 1`) and visual builder (operator "set if unset" in dropdown). Trivial to implement as part of the expression system's operator set.

---

### Gap 8: UI — Many Responses per Node — ABSORBED by Gap 4

**Original problem:** 34 player responses in a 320px sidebar accordion was unusable.

**Resolution:** The full editor (Gap 4) provides a dedicated right column for responses with ample space and scrolling. The floating toolbar shows a response count badge. No separate work needed.

---

### Gap 9: Debugger Step Limit (LOW)

**Problem:** The debugger engine has `max_steps: 500` (in `State` struct default). A full playthrough of Morte's dialogue tree (743 states with extensive branching) could exceed this.

**Current architecture:** Each `Engine.step/3` call pushes a full snapshot onto `state.snapshots` for undo support. Snapshots include `variables`, `previous_variables`, `execution_path`, `execution_log`, `history`, `call_stack`, `pending_choices`, and `status`. Thanks to Erlang's immutable data structures with structural sharing, each snapshot only allocates memory for what actually changed (a cons cell for path growth, a hash trie path for variable changes). At 1,000 steps this is a few MB — not a real problem.

**Solution:** Reactive pause instead of pre-configured limit.

1. **Increase default to 1,000** — change `max_steps: 500` → `max_steps: 1000` in `State` defstruct
2. **Pause on limit** — when `step_count >= max_steps`, instead of `:error` + `:finished`, set status to `:paused` and show a "Continue for another 1,000 steps?" prompt in the debug panel
3. **On continue** — increment `max_steps` by 1,000 and resume stepping
4. **No pre-configuration UI** — no "max steps" input field. The user doesn't need to guess a number upfront.

**Future optimization (not now):** If memory footprint becomes a concern in production, implement a sliding window on `state.snapshots` — drop the oldest N snapshots when the list exceeds a threshold (e.g., keep last 500 for undo, discard older ones). The `console` list (one entry per step, unbounded) could also be capped. Neither is urgent given Erlang's structural sharing.

**Files affected:**
- `lib/storyarn/flows/evaluator/state.ex` — `max_steps: 1000`
- `lib/storyarn/flows/evaluator/engine.ex` — change `step/3` max_steps clause from `{:error, ...}` to `{:paused, state}`
- `lib/storyarn_web/live/flow_live/handlers/debug_handlers.ex` — handle `:paused` status, show "Continue?" prompt, increment max_steps on confirm

**Effort:** Trivial.

---

## Implementation Priority

### Phase A: Foundations (enables import)

| #       | Gap                                               | Priority   | Effort      | Dependencies                                      |
|---------|---------------------------------------------------|------------|-------------|---------------------------------------------------|
| A1      | Gap 1: Nested conditions (block-based + grouping) | CRITICAL   | Medium-High | None                                              |
| ~~A2~~  | ~~Gap 3: Default/else pin on condition switch~~   | —          | —           | ✅ Already implemented (switch mode + default pin) |
| A3      | Gap 3 QoL: "Create linked flow" from exit/subflow | MEDIUM     | Low-Medium  | None                                              |
| A4      | Gap 4: Dialogue UX — Toolbar + Full Editor        | HIGH       | High        | None                                              |
| A5      | Gap 5: Expression system (Code + Builder)         | HIGH       | High        | Gap 4 (full editor provides the UI surface)       |
| A6      | Gap 6b: Flow tags                                 | MEDIUM     | Low         | None                                              |

After Phase A, the import script can generate a faithful representation of Torment's narrative.

### Phase B: Scale & Navigation (enables usability at scale)

| #      | Gap                             | Priority     | Effort | Dependencies                                                               |
|--------|---------------------------------|--------------|--------|----------------------------------------------------------------------------|
| ~~B1~~ | ~~Gap 2a: Semantic zoom / LOD~~ | ~~CRITICAL~~ | —      | ✅ Already implemented (`lod_controller.js`, 2 tiers, hysteresis, batched)  |
| B2     | Gap 2: Auto-layout              | HIGH         | Medium | None                                                                       |
| ~~B3~~ | ~~Gap 2c: Minimap~~             | ~~HIGH~~     | —      | ✅ Already implemented (`rete-minimap-plugin`, deferred after bulk load)    |
| B4     | Gap 6a: Better search           | MEDIUM       | Low    | None                                                                       |
| B5     | Gap 6c: Variable usage index    | MEDIUM       | Low    | None                                                                       |
| B6     | Gap 6d: Cross-flow navigation   | MEDIUM       | Low    | None                                                                       |

### Phase C: Polish (nice to have)

| #      | Gap                          | Priority | Effort  | Dependencies                        |
|--------|------------------------------|----------|---------|-------------------------------------|
| ~~C1~~ | ~~Gap 8: Many responses UI~~ | —        | —       | ✅ Absorbed by Gap 4 (full editor)   |
| C2     | Gap 9: Debugger step limit   | LOW      | Trivial | None                                |
| ~~C3~~ | ~~Gap 7: `set_if_unset`~~    | —        | —       | ✅ Absorbed by Gap 5 (operator `?=`) |

### Phase D: Import Script (validation)

After Phases A+B, build an Elixir mix task that:

1. Reads `docs/game_references/planescape_torment/dialogs/*.json`
2. Creates a project "Planescape: Torment"
3. Creates Sheets for variable scopes:
   - `global` sheet with 815 number blocks
   - `party` sheet with boolean blocks for `InParty` checks
   - Per-area sheets (`ar0400`, `ar0605`, etc.)
   - `stats` sheet for character stats
4. Creates folder Flows by area (33 areas → 33 folder flows)
5. Creates one Flow per dialogue file (806 flows), tagged by area
6. For each dialogue state:
   - Entry points (states with conditions, not targeted by transitions) → Condition node (switch mode) at flow start
   - NPC text → Dialogue node (speaker from sheet if identifiable)
   - Player responses → Dialogue responses with conditions and instructions
   - Actions → Inline response instructions (Gap 5) or Instruction nodes
   - Cross-references (`next_dialog` to different file) → Subflow nodes
7. Runs auto-layout on each flow
8. Creates Maps for the 33 areas with pins linking to flows

**Expected result:** A fully navigable Planescape: Torment project in Storyarn with ~800 flows, ~16,000 dialogue nodes, all variables, all branching logic, organized by area with maps.

---

## Success Criteria

After all phases:

- [ ] Can open Morte's dialogue (743 states) without performance degradation
- [ ] Can navigate the full flow visually using minimap + semantic zoom
- [ ] Condition nodes express all Torment branching patterns (nested AND/OR, switch priority)
- [ ] Response instructions work inline (no need for 9,461 extra Instruction nodes)
- [ ] Conditions and instructions editable in both Builder and Code modes, synced bidirectionally
- [ ] Dialogue nodes use floating toolbar + full editor (no sidebar scrolling)
- [ ] Node deletion via keyboard (Delete/Backspace) with undo — no confirmation dialogs
- [ ] Can search across 806 flows and filter by tags
- [ ] Can see which flows read/write a specific variable
- [ ] Story Player can play through a Torment dialogue tree with variable evaluation
- [ ] Canvas auto-layout produces readable tree structures for imported flows

---

## Open Questions

1. **Split vs single flow for large dialogues?** Morte (743 states) as one flow or split into sub-flows per narrative phase? Sub-flows are cleaner but add navigation overhead. Recommendation: let the user choose; import as single flow but provide a "split by entry points" action.

2. **Nested condition UI:** How deep should nesting go? Recommendation: max 3 levels. Deeper nesting is unreadable and should be split into multiple condition nodes.

3. **Auto-layout algorithm:** Dagre (simpler, good for trees) vs ELK (more powerful, handles complex graphs)? Recommendation: start with Dagre, evaluate ELK if results are poor for highly connected graphs.

4. **Import as mix task vs UI feature?** The import script is a one-off validation tool. Should we build a general "import" UI? Recommendation: mix task for now. General import is a future feature.
