# ConditionBuilder & InstructionBuilder — Vue Migration Plan

## Current Architecture

Both builders use the same pattern:

- **Elixir component** (`condition_builder.ex` / `instruction_builder.ex`) — thin HEEx wrapper with `phx-hook` + `phx-update="ignore"`, passes all data via `data-*` attributes
- **LiveView hook** (`condition_builder.js` / `instruction_builder.js`) — reads `data-*`, instantiates core builder, handles `handleEvent` for collaboration
- **Core builder** (`condition_builder_core.js` / `instruction_builder_core.js`) — imperative DOM rendering, framework-agnostic, accepts `pushEvent` callback
- **Supporting modules** — rule rows, comboboxes, sentence templates, utils

### File Map & Line Counts

```
ConditionBuilder (1275 lines total):
├── lib/storyarn_web/components/condition_builder.ex          (121 lines) — HEEx wrapper
├── assets/js/hooks/condition_builder.js                      (132 lines) — LV hook
├── assets/js/screenplay/builders/condition_builder_core.js   (398 lines) — Core rendering
├── assets/js/condition_builder/condition_block.js            (210 lines) — Block UI
├── assets/js/condition_builder/condition_group.js            (178 lines) — Group UI
├── assets/js/condition_builder/condition_rule_row.js         (359 lines) — Rule row with comboboxes
├── assets/js/condition_builder/condition_sentence_templates.js (65 lines) — Operator labels
└── assets/js/condition_builder/condition_utils.js             (65 lines) — ID gen, logic toggle

InstructionBuilder (741 lines total):
├── lib/storyarn_web/components/instruction_builder.ex        (similar to condition)
├── assets/js/hooks/instruction_builder.js                     (95 lines) — LV hook
├── assets/js/screenplay/builders/instruction_builder_core.js (169 lines) — Core rendering
├── assets/js/instruction_builder/assignment_row.js           (489 lines) — Row with comboboxes
├── assets/js/instruction_builder/combobox.js                 (387 lines) — Custom combobox
└── assets/js/instruction_builder/sentence_templates.js       (187 lines) — Operation labels
```

## Data Structures

### Condition (block format)

```json
{
  "logic": "all", // "all" | "any" — top-level logic
  "blocks": [
    {
      "id": "block_abc123",
      "type": "block", // "block" | "group"
      "logic": "all", // inner logic for this block's rules
      "label": "", // only in switch_mode
      "rules": [
        {
          "id": "rule_xyz789",
          "sheet": "main-characters", // sheet shortcut or null
          "variable": "health_points", // variable name
          "operator": "greater_than", // see operator list below
          "value": "50" // comparison value
        }
      ]
    },
    {
      "id": "group_def456",
      "type": "group",
      "logic": "any",
      "blocks": [
        /* nested blocks */
      ]
    }
  ]
}
```

### Operators (context-dependent by variable type)

| Variable Type | Available Operators                                                                            |
| ------------- | ---------------------------------------------------------------------------------------------- |
| number        | equals, not_equals, greater_than, greater_than_or_equal, less_than, less_than_or_equal, is_nil |
| text          | equals, not_equals, contains, not_contains, starts_with, ends_with, is_empty, is_nil           |
| boolean       | is_true, is_false, is_nil                                                                      |
| select        | equals, not_equals, is_nil                                                                     |
| multi_select  | contains, not_contains, is_nil                                                                 |
| date          | equals, not_equals, before, after, is_nil                                                      |

### Assignment

```json
[
  {
    "id": "assign_abc123",
    "sheet": "main-characters",
    "variable": "health_points",
    "operation": "add", // "set" | "add" | "subtract" | "multiply" | "toggle"
    "value": "10"
  }
]
```

### Operations (context-dependent by variable type)

| Variable Type | Available Operations         |
| ------------- | ---------------------------- |
| number        | set, add, subtract, multiply |
| text          | set                          |
| boolean       | set, toggle                  |
| select        | set                          |
| multi_select  | set, add, subtract           |
| date          | set                          |

## Variable Data Format

Variables are passed as a flat list, each with:

```json
{
  "ref": "main-characters.health_points",
  "sheet_shortcut": "main-characters",
  "sheet_name": "Main Characters",
  "variable_name": "health_points",
  "block_type": "number",      // determines available operators/operations
  "is_constant": false,
  "options": [...]              // for select/multi_select types
}
```

The builders group these by `sheet_shortcut` for the combobox UI.

## Combobox Behavior

Both builders use a custom combobox (not a native select):

1. **Two-level selection**: first select sheet, then select variable within that sheet
2. **Searchable**: filter variables by typing
3. **Grouped display**: variables grouped by sheet with sheet headers
4. **Context-aware**: selecting a variable updates available operators/operations
5. **Floating popover**: body-appended to escape overflow containers

## Features to Port

### ConditionBuilder

- [ ] Block format with nested groups
- [ ] Logic toggle (all/any) at top level and per block
- [ ] Rule rows with sheet → variable → operator → value comboboxes
- [ ] Operator filtering by variable type
- [ ] Value input adapts to operator (no value for is_true/is_false/is_nil/is_empty)
- [ ] Add block button
- [ ] Remove block button
- [ ] Selection mode for grouping blocks
- [ ] Group/ungroup blocks
- [ ] Switch mode (each block = labeled output, for condition nodes)
- [ ] Empty state display
- [ ] Read-only mode (can_edit=false)
- [ ] Collaboration: receive updates via handleEvent("node_updated")
- [ ] Context-aware event pushing (node condition, response condition, zone/pin condition)
- [ ] Translations for all UI strings

### InstructionBuilder

- [ ] Assignment rows with sheet → variable → operation → value
- [ ] Operation filtering by variable type
- [ ] Value input hidden for "toggle" operation
- [ ] Add assignment button
- [ ] Remove assignment button
- [ ] Reorder assignments (optional, current JS doesn't have this)
- [ ] Empty state display
- [ ] Read-only mode
- [ ] Collaboration: receive updates via handleEvent("node_updated")
- [ ] Translations

## Migration Strategy

### Option A: Port to Vue (recommended)

Rewrite both builders as Vue components using shadcn-vue primitives:

- `ConditionBuilder.vue` — main component
- `ConditionBlock.vue` — single block with rules
- `ConditionGroup.vue` — grouped blocks
- `ConditionRule.vue` — single rule row
- `VariableCombobox.vue` — sheet → variable two-level select (reused by both builders)
- `InstructionBuilder.vue` — main component
- `AssignmentRow.vue` — single assignment row

### Option B: Wrap existing JS (faster, less clean)

Create Vue wrappers that mount the existing imperative JS builders in `onMounted`:

- `ConditionBuilderWrapper.vue` — mounts `createConditionBuilder()` in a ref div
- `InstructionBuilderWrapper.vue` — mounts `createInstructionBuilder()` in a ref div

Option B is faster but creates a dependency on the old JS code. Option A is cleaner for the long-term Vue migration.

### Shared Component: VariableCombobox

Both builders need the same variable selection UI. Create once, use in both:

- Uses shadcn `Command` (cmdk) for searchable, grouped selection
- Two-step: sheet group → variable within sheet
- Shows variable type icon/badge
- Filters by type when needed (e.g., only number variables for number operations)

## Storybook Stories Needed

Each component needs a Phoenix Storybook story to verify:

1. **ConditionBuilder** — empty, single rule, multiple blocks, grouped blocks, switch mode, read-only
2. **InstructionBuilder** — empty, single assignment, multiple, read-only
3. **VariableCombobox** — with various variable types, search, selection
4. All stories must verify `pushEvent` is called with correct payloads

## Used In

### ConditionBuilder

- Flow editor: condition nodes (switch_mode=true for multi-output)
- Flow editor: response conditions on dialogue choices
- Scene editor: zone conditions (hide/disable)
- Scene editor: pin conditions (hide/disable)
- Screenplay editor: inline condition blocks (TipTap NodeView)

### InstructionBuilder

- Flow editor: instruction nodes
- Scene editor: zone actions (on-enter assignments)
- Screenplay editor: inline instruction blocks (TipTap NodeView)
