# Nested Conditions (Block-Based with Grouping)

> **Gap Reference:** Gap 1 from `docs/plans/COMPLEX_NARRATIVE_STRESS_TEST.md`
>
> **Priority:** CRITICAL
>
> **Effort:** Medium-High
>
> **Dependencies:** None
>
> **Previous:** N/A (first document in stress test chain)
>
> **Next:** [`02_CREATE_LINKED_FLOW.md`](./02_CREATE_LINKED_FLOW.md)
>
> **Last Updated:** February 20, 2026

---

## Context and Current State

The condition system is used by condition nodes (switch mode and normal mode), dialogue response conditions, and the Story Player/debugger evaluator. Today it supports only a **flat list of rules** with a single top-level `all`/`any` logic operator. Complex Planescape: Torment patterns like `(A AND B) OR (C AND D)` cannot be expressed in a single condition -- they require chaining multiple condition nodes, which is verbose and hard to read.

### Current data format

```json
{
  "logic": "all",
  "rules": [
    {"id": "rule_1", "sheet": "mc.jaime", "variable": "health", "operator": "greater_than", "value": "50"},
    {"id": "rule_2", "sheet": "party", "variable": "annah", "operator": "is_true"}
  ]
}
```

### Target data format

```json
{
  "logic": "all",
  "blocks": [
    {
      "id": "block_1", "type": "block", "logic": "all",
      "rules": [
        {"id": "rule_1", "sheet": "global", "variable": "annah", "operator": "equals", "value": "0"},
        {"id": "rule_2", "sheet": "party", "variable": "annah_present", "operator": "is_true"}
      ]
    },
    {
      "id": "group_1", "type": "group", "logic": "and",
      "blocks": [
        {"id": "block_2", "type": "block", "logic": "all", "rules": [...]},
        {"id": "block_3", "type": "block", "logic": "all", "rules": [...]}
      ]
    }
  ]
}
```

### Backwards compatibility rule

The old format `{"logic": "all", "rules": [...]}` remains valid everywhere. It is treated as a single block. Auto-upgrade to the new format happens on first edit in the builder. The evaluator handles both formats transparently.

---

## Visual Design

### Current state: flat rules

Today the condition builder renders a flat list of rules with a single AND/OR toggle at the top:

```
┌─────────────────────────────────────────────────────────────┐
│  Match  [ALL v]  of the following                           │
│                                                             │
│  [global    ] · [annah         ] [equals       ] [0      ] │
│  [party     ] · [annah_present ] [is true      ]        ✕  │
│                                                             │
│  + Add condition                                            │
└─────────────────────────────────────────────────────────────┘
```

This cannot express `(A AND B) OR (C AND D)` — only flat AND or flat OR.

### New state: single block (auto-upgraded from flat)

When an existing flat condition is opened for the first time, it auto-upgrades
into a single block. Visually identical to before — the user sees no change:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌ Block ─────────────────────────────────────────────┐     │
│  │  Match  [ALL v]  of the following                  │     │
│  │                                                    │     │
│  │  [global ] · [annah         ] [equals  ] [0     ]  │     │
│  │  [party  ] · [annah_present ] [is true ]        ✕  │     │
│  │                                                    │     │
│  │  + Add rule                                     ✕  │     │
│  └────────────────────────────────────────────────────┘     │
│                                                             │
│  + Add block    Group                                       │
└─────────────────────────────────────────────────────────────┘
```

Key differences from current:
- Rules are visually contained inside a **block card** (subtle border, rounded)
- Each block has its own AND/OR toggle and "+ Add rule" button
- Block card has a remove button (✕) in the top-right corner
- Bottom action bar shows "+ Add block" and "Group" buttons

### New state: multiple blocks

When the user clicks "+ Add block", a second block card appears. A top-level
AND/OR toggle appears between them:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌ Block ─────────────────────────────────────────────┐     │
│  │  Match  [ALL v]  of the following                  │     │
│  │                                                    │     │
│  │  [global ] · [annah         ] [equals  ] [0     ]  │     │
│  │  [party  ] · [annah_present ] [is true ]           │     │
│  │                                                    │     │
│  │  + Add rule                                     ✕  │     │
│  └────────────────────────────────────────────────────┘     │
│                                                             │
│                    ── [OR v] ──                              │
│                                                             │
│  ┌ Block ─────────────────────────────────────────────┐     │
│  │  Match  [ALL v]  of the following                  │     │
│  │                                                    │     │
│  │  [global ] · [know_annah    ] [greater ] [2     ]  │     │
│  │  [global ] · [fortress      ] [equals  ] [3     ]  │     │
│  │                                                    │     │
│  │  + Add rule                                     ✕  │     │
│  └────────────────────────────────────────────────────┘     │
│                                                             │
│  + Add block    Group                                       │
└─────────────────────────────────────────────────────────────┘
```

This expresses: `(annah == 0 AND annah_present) OR (know_annah > 2 AND fortress == 3)`

The top-level toggle applies between ALL block cards. Each block's internal
toggle applies between its own rules.

### New state: grouped blocks

When the user selects 2+ blocks and clicks "Group selected", they merge into a
group. Groups have a colored left border and their own AND/OR toggle:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌ Block ─────────────────────────────────────────────┐     │
│  │  [global ] · [chapter       ] [greater ] [2     ]  │     │
│  │                                                 ✕  │     │
│  └────────────────────────────────────────────────────┘     │
│                                                             │
│                    ── [AND v] ──                             │
│                                                             │
│  ┃ Group ── Match [ALL v] ───────────────────────────────┐  │
│  ┃                                                       │  │
│  ┃  ┌ Block ──────────────────────────────────────┐      │  │
│  ┃  │  [global ] · [annah      ] [equals  ] [0  ] │      │  │
│  ┃  │  [party  ] · [annah_pres ] [is true ]       │      │  │
│  ┃  │  + Add rule                                  │      │  │
│  ┃  └─────────────────────────────────────────────┘      │  │
│  ┃                                                       │  │
│  ┃                    ── [OR v] ──                        │  │
│  ┃                                                       │  │
│  ┃  ┌ Block ──────────────────────────────────────┐      │  │
│  ┃  │  [global ] · [know_annah ] [greater ] [2  ] │      │  │
│  ┃  │  [global ] · [fortress   ] [equals  ] [3  ] │      │  │
│  ┃  │  + Add rule                                  │      │  │
│  ┃  └─────────────────────────────────────────────┘      │  │
│  ┃                                                       │  │
│  ┃  + Add block                          Ungroup         │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  + Add block    Group                                       │
└─────────────────────────────────────────────────────────────┘
```

This expresses: `chapter > 2 AND ((annah == 0 AND annah_present) OR (know_annah > 2 AND fortress == 3))`

Key visual elements of a group:
- Colored left border (┃) distinguishes groups from standalone blocks
- Group has its own AND/OR toggle between its inner blocks
- "Ungroup" button dissolves the group back into standalone blocks
- "+ Add block" inside the group adds blocks to that group
- Groups cannot contain other groups (max 1 level of nesting)

### Selection mode (grouping workflow)

When the user clicks "Group", the builder enters selection mode. Checkboxes
appear on each block card. The action bar changes:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ☑ ┌ Block ───────────────────────────────────────────┐     │
│    │  [global ] · [annah         ] [equals  ] [0     ]│     │
│    │  [party  ] · [annah_present ] [is true ]         │     │
│    └──────────────────────────────────────────────────┘     │
│                                                             │
│  ☑ ┌ Block ───────────────────────────────────────────┐     │
│    │  [global ] · [know_annah    ] [greater ] [2     ]│     │
│    │  [global ] · [fortress      ] [equals  ] [3     ]│     │
│    └──────────────────────────────────────────────────┘     │
│                                                             │
│  ☐ ┌ Block ───────────────────────────────────────────┐     │
│    │  [global ] · [chapter       ] [greater ] [2     ]│     │
│    └──────────────────────────────────────────────────┘     │
│                                                             │
│  [Group selected (2)]    Cancel                             │
└─────────────────────────────────────────────────────────────┘
```

- Blocks become non-editable during selection (no combobox interaction)
- Checkboxes appear left of each block card
- Action bar shows "Group selected (N)" (enabled when N >= 2) + "Cancel"
- Clicking "Group selected" wraps checked blocks into a new group
- Clicking "Cancel" exits selection mode without changes

### Switch mode (condition node with cases)

In switch mode, each block's first rule gets a label input for the output pin
name. Blocks work the same way — each block is one "case":

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌ Block ─────────────────────────────────────────────┐     │
│  │  [Annah path ]:                                    │     │
│  │  [global ] · [annah         ] [equals  ] [0     ]  │     │
│  │  [party  ] · [annah_present ] [is true ]        ✕  │     │
│  │  + Add rule                                     ✕  │     │
│  └────────────────────────────────────────────────────┘     │
│                                                             │
│  ┌ Block ─────────────────────────────────────────────┐     │
│  │  [Fortress path ]:                                 │     │
│  │  [global ] · [fortress      ] [equals  ] [3     ]  │     │
│  │  + Add rule                                     ✕  │     │
│  └────────────────────────────────────────────────────┘     │
│                                                             │
│  + Add block                                                │
└─────────────────────────────────────────────────────────────┘
```

In switch mode:
- No top-level AND/OR toggle (each block is an independent case)
- No "Group" button (grouping doesn't apply to switch cases)
- Each block has a label input at the top (the output pin name)
- The label comes from the first rule's `label` field

### Key files (current state)

| File                                                          | Role                                                                                                                                                                                                                                                                                    |
|---------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `lib/storyarn/flows/condition.ex`                             | Parsing, validation, sanitization, serialization. Functions: `new/1`, `parse/1`, `to_json/1`, `add_rule/2`, `remove_rule/2`, `update_rule/4`, `set_logic/2`, `sanitize/1`, `validate/1`, `has_rules?/1`. Known keys whitelist: `id`, `sheet`, `variable`, `operator`, `value`, `label`. |
| `lib/storyarn/flows/evaluator/condition_eval.ex`              | `evaluate/2` returns `{boolean, [rule_results]}`. Iterates flat `rules` list, calls `complete_rule?/1` then `evaluate_rule/1`.                                                                                                                                                          |
| `test/storyarn/flows/evaluator/condition_eval_test.exs`       | 30+ tests covering all operators, logic modes, edge cases. No tests for `condition.ex` itself.                                                                                                                                                                                          |
| `assets/js/screenplay/builders/condition_builder_core.js`     | `createConditionBuilder({container, condition, variables, canEdit, switchMode, context, eventName, pushEvent, translations})`. Manages `currentCondition.rules` as a flat array, renders each via `createConditionRuleRow`.                                                             |
| `assets/js/condition_builder/condition_rule_row.js`           | `createConditionRuleRow(opts)`. Returns `{getRule(), focusFirstEmpty(), destroy()}`. Renders comboboxes for sheet, variable, operator, value.                                                                                                                                           |
| `assets/js/condition_builder/condition_sentence_templates.js` | `CONDITION_OPERATORS_BY_TYPE`, `OPERATOR_LABELS`, `NO_VALUE_OPERATORS` (Set), `operatorsForType(type)`.                                                                                                                                                                                 |
| `assets/js/hooks/condition_builder.js`                        | LiveView hook. Reads `data-*` on mount, creates builder, routes events. Pushes `"update_condition_builder"` or custom event name. Listens to `"node_updated"` for collaboration.                                                                                                        |
| `lib/storyarn_web/components/condition_builder.ex`            | HEEx component. Renders `<div phx-hook="ConditionBuilder" phx-update="ignore" data-*={...}>`. Passes condition, variables, translations.                                                                                                                                                |

---

## Subtask 1: Backend Data Model + Validation (`condition.ex`)

### Description

Extend `Storyarn.Flows.Condition` to understand the new block-based format while preserving full backwards compatibility with the flat-rules format. All existing callers that produce or consume `{"logic": "...", "rules": [...]}` must continue working unchanged.

### Files Affected

- `lib/storyarn/flows/condition.ex` -- extend all public functions

### Implementation Steps

**1.1. Add new format detection to `parse/1`**

The existing `parse/1` pattern-matches on `%{"logic" => logic, "rules" => rules}`. Add a second clause that matches `%{"logic" => logic, "blocks" => blocks}`:

```elixir
# In parse/1, after the existing {:ok, %{"logic" => logic, "rules" => rules}} clause:
{:ok, %{"logic" => logic, "blocks" => blocks}}
when logic in @logic_types and is_list(blocks) ->
  %{
    "logic" => logic,
    "blocks" => Enum.map(blocks, &normalize_block/1) |> Enum.reject(&is_nil/1)
  }
```

**1.2. Add `normalize_block/1` private function**

Handles both block types (`"block"` with rules, `"group"` with nested blocks):

```elixir
defp normalize_block(%{"type" => "block"} = block) when is_map(block) do
  %{
    "id" => block["id"] || generate_block_id(),
    "type" => "block",
    "logic" => normalize_logic(block["logic"]),
    "rules" => normalize_rules(block["rules"])
  }
end

defp normalize_block(%{"type" => "group"} = group) when is_map(group) do
  inner_blocks =
    (group["blocks"] || [])
    |> Enum.filter(&is_map/1)
    |> Enum.map(&normalize_block/1)
    |> Enum.reject(&is_nil/1)

  # Groups can only contain blocks, not other groups
  inner_blocks = Enum.filter(inner_blocks, fn b -> b["type"] == "block" end)

  %{
    "id" => group["id"] || generate_block_id(),
    "type" => "group",
    "logic" => normalize_logic(group["logic"]),
    "blocks" => inner_blocks
  }
end

defp normalize_block(_), do: nil
```

**1.3. Helper functions**

```elixir
defp normalize_logic(logic) when logic in @logic_types, do: logic
defp normalize_logic(_), do: "all"

defp normalize_rules(rules) when is_list(rules) do
  rules
  |> Enum.filter(&is_map/1)
  |> Enum.map(&normalize_rule/1)
  |> Enum.reject(&is_nil/1)
end

defp normalize_rules(_), do: []

defp generate_block_id do
  "block_#{:erlang.unique_integer([:positive])}"
end
```

**1.4. Extend `to_json/1` for new format**

Add a clause before the existing `to_json/1`:

```elixir
def to_json(%{"logic" => logic, "blocks" => blocks}) when is_list(blocks) do
  normalized_blocks = Enum.map(blocks, &normalize_block/1) |> Enum.reject(&is_nil/1)
  if normalized_blocks == [], do: nil, else: Jason.encode!(%{"logic" => logic, "blocks" => normalized_blocks})
end
```

**1.5. Extend `sanitize/1` for new format**

Add a clause matching blocks format:

```elixir
def sanitize(%{"logic" => logic, "blocks" => blocks}) when is_list(blocks) do
  sanitized_logic = if logic in @logic_types, do: logic, else: "all"

  sanitized_blocks =
    blocks
    |> Enum.filter(&is_map/1)
    |> Enum.map(&sanitize_block/1)
    |> Enum.reject(&is_nil/1)

  %{"logic" => sanitized_logic, "blocks" => sanitized_blocks}
end

defp sanitize_block(%{"type" => "block"} = block) do
  %{
    "id" => block["id"] || generate_block_id(),
    "type" => "block",
    "logic" => normalize_logic(block["logic"]),
    "rules" =>
      (block["rules"] || [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn rule -> rule |> Map.take(@known_keys) |> normalize_rule() end)
      |> Enum.reject(&is_nil/1)
  }
end

defp sanitize_block(%{"type" => "group"} = group) do
  inner_blocks =
    (group["blocks"] || [])
    |> Enum.filter(&is_map/1)
    |> Enum.map(&sanitize_block/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn b -> b["type"] == "block" end)

  %{
    "id" => group["id"] || generate_block_id(),
    "type" => "group",
    "logic" => normalize_logic(group["logic"]),
    "blocks" => inner_blocks
  }
end

defp sanitize_block(_), do: nil
```

**1.6. Extend `validate/1` for new format**

```elixir
def validate(%{"logic" => logic, "blocks" => blocks})
    when logic in @logic_types and is_list(blocks) do
  if Enum.all?(blocks, &valid_block_structure?/1) do
    {:ok, %{"logic" => logic, "blocks" => blocks}}
  else
    {:error, "Invalid block structure"}
  end
end

defp valid_block_structure?(%{"type" => "block", "rules" => rules}) when is_list(rules) do
  Enum.all?(rules, &valid_rule_structure?/1)
end

defp valid_block_structure?(%{"type" => "group", "blocks" => blocks}) when is_list(blocks) do
  Enum.all?(blocks, &valid_block_structure?/1)
end

defp valid_block_structure?(_), do: false
```

**1.7. Extend `has_rules?/1` for new format**

```elixir
def has_rules?(%{"blocks" => blocks}) when is_list(blocks) do
  Enum.any?(blocks, &block_has_rules?/1)
end

defp block_has_rules?(%{"type" => "block", "rules" => rules}) when is_list(rules) do
  Enum.any?(rules, &valid_rule?/1)
end

defp block_has_rules?(%{"type" => "group", "blocks" => blocks}) when is_list(blocks) do
  Enum.any?(blocks, &block_has_rules?/1)
end

defp block_has_rules?(_), do: false
```

**1.8. Add `upgrade/1` helper to convert old format to new**

```elixir
@doc """
Upgrades a flat-rules condition to the block-based format.
If already in block format, returns as-is.
"""
@spec upgrade(map() | nil) :: map()
def upgrade(nil), do: new_block_condition()
def upgrade(%{"blocks" => _} = condition), do: condition

def upgrade(%{"logic" => logic, "rules" => rules}) when is_list(rules) do
  block = %{
    "id" => generate_block_id(),
    "type" => "block",
    "logic" => logic,
    "rules" => rules
  }

  %{"logic" => "all", "blocks" => [block]}
end

def upgrade(_), do: new_block_condition()

@doc "Creates a new empty block-based condition."
@spec new_block_condition(String.t()) :: map()
def new_block_condition(logic \\ "all") do
  %{"logic" => logic, "blocks" => []}
end
```

**1.9. Keep all existing flat-rules functions unchanged**

The existing `add_rule/2`, `remove_rule/2`, `update_rule/4`, `set_logic/2` continue to work on flat-rules format. They are used by the legacy/simple code paths and do not need modification.

### Test Battery

Create `test/storyarn/flows/condition_test.exs`:

```elixir
defmodule Storyarn.Flows.ConditionTest do
  use ExUnit.Case, async: true
  alias Storyarn.Flows.Condition

  # --- Flat format (existing behavior, regression tests) ---

  describe "parse/1 flat format" do
    test "parses valid flat condition"
    test "returns nil for empty string"
    test "returns nil for nil"
    test "returns :legacy for non-JSON string"
    test "returns :legacy for valid JSON with wrong structure"
  end

  describe "to_json/1 flat format" do
    test "serializes flat condition"
    test "returns nil for empty rules"
    test "returns nil for nil"
  end

  describe "sanitize/1 flat format" do
    test "removes unknown keys from rules"
    test "rejects non-map rules"
    test "defaults invalid logic to all"
  end

  describe "validate/1 flat format" do
    test "accepts valid flat condition"
    test "rejects invalid structure"
  end

  describe "has_rules?/1 flat format" do
    test "returns false for nil"
    test "returns false for empty rules"
    test "returns true when complete rule exists"
    test "returns false when all rules are incomplete"
  end

  # --- Block format (new behavior) ---

  describe "parse/1 block format" do
    test "parses condition with blocks"
    test "parses condition with group containing blocks"
    test "rejects groups within groups (flattens to blocks only)"
    test "generates IDs for blocks missing them"
    test "normalizes block logic to 'all' when invalid"
  end

  describe "to_json/1 block format" do
    test "serializes block-based condition"
    test "returns nil for empty blocks list"
    test "preserves group structure in serialization"
  end

  describe "sanitize/1 block format" do
    test "sanitizes blocks with unknown keys in rules"
    test "sanitizes group containing blocks"
    test "rejects non-block items in groups"
    test "defaults to empty block condition for invalid input"
  end

  describe "validate/1 block format" do
    test "accepts valid block-based condition"
    test "accepts valid condition with groups"
    test "rejects block with invalid rules"
  end

  describe "has_rules?/1 block format" do
    test "returns true when a block has complete rules"
    test "returns true when a group contains a block with rules"
    test "returns false when all blocks have empty rules"
  end

  # --- Upgrade ---

  describe "upgrade/1" do
    test "converts flat rules to single-block format"
    test "passes through block format unchanged"
    test "returns empty block condition for nil"
    test "returns empty block condition for invalid input"
    test "preserves rules during upgrade"
    test "preserves logic during upgrade (as inner block logic)"
  end

  # --- Backwards compatibility ---

  describe "backwards compatibility" do
    test "existing flat-format add_rule/2 still works"
    test "existing flat-format remove_rule/2 still works"
    test "existing flat-format update_rule/4 still works"
    test "existing flat-format set_logic/2 still works"
    test "parse -> to_json roundtrip preserves flat format"
    test "parse -> to_json roundtrip preserves block format"
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 2: Backend Evaluation (`condition_eval.ex`)

### Description

Extend `ConditionEval.evaluate/2` to recursively evaluate block-based conditions. A block evaluates its rules with its own logic. A group evaluates its inner blocks with its own logic. The top-level evaluates its blocks/groups with the top-level logic.

### Files Affected

- `lib/storyarn/flows/evaluator/condition_eval.ex`

### Implementation Steps

**2.1. Add new `evaluate/2` clause for block format**

Before the existing clause that matches `%{"logic" => logic, "rules" => rules}`, add:

```elixir
def evaluate(%{"logic" => logic, "blocks" => blocks}, variables)
    when is_list(blocks) do
  block_results = Enum.map(blocks, &evaluate_block(&1, variables))

  # Flatten all rule results from nested blocks for detailed reporting
  all_rule_results = Enum.flat_map(block_results, fn {_passed, results} -> results end)

  if block_results == [] do
    {true, []}
  else
    result =
      case logic do
        "all" -> Enum.all?(block_results, fn {passed, _} -> passed end)
        "any" -> Enum.any?(block_results, fn {passed, _} -> passed end)
        _ -> Enum.all?(block_results, fn {passed, _} -> passed end)
      end

    {result, all_rule_results}
  end
end
```

**2.2. Add `evaluate_block/2` private function**

```elixir
defp evaluate_block(%{"type" => "block", "logic" => logic, "rules" => rules}, variables)
     when is_list(rules) do
  # Same logic as the flat-rules evaluate, but scoped to this block
  rule_results =
    rules
    |> Enum.filter(&complete_rule?/1)
    |> Enum.map(&evaluate_rule(&1, variables))

  if rule_results == [] do
    {true, []}
  else
    result =
      case logic do
        "all" -> Enum.all?(rule_results, & &1.passed)
        "any" -> Enum.any?(rule_results, & &1.passed)
        _ -> Enum.all?(rule_results, & &1.passed)
      end

    {result, rule_results}
  end
end

defp evaluate_block(%{"type" => "group", "logic" => logic, "blocks" => blocks}, variables)
     when is_list(blocks) do
  block_results = Enum.map(blocks, &evaluate_block(&1, variables))
  all_rule_results = Enum.flat_map(block_results, fn {_passed, results} -> results end)

  if block_results == [] do
    {true, []}
  else
    result =
      case logic do
        "all" -> Enum.all?(block_results, fn {passed, _} -> passed end)
        "any" -> Enum.any?(block_results, fn {passed, _} -> passed end)
        _ -> Enum.all?(block_results, fn {passed, _} -> passed end)
      end

    {result, all_rule_results}
  end
end

defp evaluate_block(_, _variables), do: {true, []}
```

**2.3. Make `evaluate_rule/2` public spec accessible to both clauses**

No change needed -- `evaluate_rule/2` is already public and used by both the flat and block paths.

### Test Battery

Update `test/storyarn/flows/evaluator/condition_eval_test.exs` -- add new describe blocks:

```elixir
# Add after existing describe blocks:

describe "evaluate/2 block format" do
  setup do
    variables = %{
      "mc.jaime.health" => var(80, "number"),
      "mc.jaime.alive" => var(true, "boolean"),
      "global.quest" => var(3, "number")
    }
    {:ok, variables: variables}
  end

  test "single block — all rules pass → true", %{variables: v}
  test "single block — one rule fails → false (all logic)", %{variables: v}
  test "two blocks — all logic — both pass → true", %{variables: v}
  test "two blocks — all logic — one fails → false", %{variables: v}
  test "two blocks — any logic — one passes → true", %{variables: v}
  test "two blocks — any logic — all fail → false", %{variables: v}
  test "empty blocks list → true"
  test "block with no complete rules → true"
end

describe "evaluate/2 group format" do
  setup do
    variables = %{
      "global.annah" => var(0, "number"),
      "party.annah_present" => var(true, "boolean"),
      "global.know_annah" => var(3, "number"),
      "global.fortress" => var(3, "number")
    }
    {:ok, variables: variables}
  end

  test "group with AND logic — both inner blocks pass → group passes", %{variables: v}
  test "group with AND logic — one inner block fails → group fails", %{variables: v}
  test "group with OR logic — one inner block passes → group passes", %{variables: v}
  test "top-level ANY — block passes OR group passes → true", %{variables: v}
  test "top-level ALL — block fails AND group passes → false", %{variables: v}
  test "empty group → true"
  test "rule results are flattened across all blocks and groups", %{variables: v}
end

describe "evaluate/2 mixed format backwards compat" do
  test "flat-rules format still evaluates correctly"
  test "evaluate_string/2 handles block format JSON"
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 3: JS Block Card Component (`condition_block.js`)

### Description

Create a new JS module that renders a single condition block as a visual card. This is the fundamental building block of the new UI. A block card contains: a logic toggle (when 2+ rules), the existing rule rows, an "Add rule" button, and a remove button. This replaces the direct rule-row rendering that `condition_builder_core.js` currently does.

### Files Affected

- New: `assets/js/condition_builder/condition_block.js`

### Implementation Steps

**3.1. Module structure**

Follow the same pattern as `condition_rule_row.js`: a factory function that takes options, renders into a container, and returns a public API.

```javascript
/**
 * Renders a single condition block card.
 *
 * A block is a visual card containing a set of rules with its own AND/OR
 * logic toggle. Mirrors the current flat-rules rendering but wrapped in
 * a card container.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - Card container element
 * @param {Object} opts.block - Block data {id, type, logic, rules}
 * @param {Array} opts.variables - All project variables
 * @param {Array} opts.sheetsWithVariables - Grouped sheets [{shortcut, name, vars}]
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {boolean} opts.switchMode - Whether in switch mode
 * @param {Object} opts.translations - Translated strings
 * @param {Function} opts.onChange - Callback when block changes: (updatedBlock) => void
 * @param {Function} opts.onRemove - Callback to remove this block: () => void
 * @returns {{ getBlock: Function, destroy: Function }}
 */
export function createConditionBlock(opts) { ... }
```

**3.2. Rendering logic**

- Outer container: `div.condition-block` with a card-like style (border, rounded corners, padding)
- If `block.rules.length >= 2` and not `switchMode`: render the AND/OR logic toggle for this block (reuse the same toggle pattern from `condition_builder_core.js#renderLogicToggle`)
- For each rule: create a `div` container and call `createConditionRuleRow(...)` -- delegate fully, do not duplicate
- "Add rule" button at the bottom of the card (same pattern as current builder)
- Remove block button (X) in the top-right corner, visible on hover

**3.3. Callback wiring**

- When a rule changes (`onChange` from rule row), update the block's rules array and call `opts.onChange(updatedBlock)`
- When a rule is removed, splice from the rules array, call `opts.onChange`, and re-render
- When logic is toggled, update `block.logic` and call `opts.onChange`
- The "Add rule" button creates a new empty rule, pushes to `block.rules`, calls `opts.onChange`, re-renders, and focuses the new row's first empty field

**3.4. Public API**

```javascript
return {
  getBlock: () => ({ ...currentBlock, rules: [...currentBlock.rules] }),
  destroy: () => { destroyRows(); container.innerHTML = ""; }
};
```

### Test Battery

This is a client-side JS module. Testing approach:

- Manual test: Create a condition node, verify the block card renders with the expected layout
- Verify: changing logic toggle calls onChange with updated logic
- Verify: removing a rule updates the block and re-renders
- Verify: adding a rule appends to the block and focuses the new row
- Verify: read-only mode (canEdit=false) hides add/remove buttons

No automated test file -- JS components in this project are tested through integration (LiveView tests) and manual verification.

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 4: JS Group Wrapper Component (`condition_group.js`)

### Description

Create a new JS module that renders a condition group -- a visual wrapper around multiple blocks. A group has its own AND/OR toggle, an "Add block" button, an "Ungroup" button, and renders its inner blocks using `createConditionBlock`. Groups cannot contain other groups (max nesting: 1 level).

### Files Affected

- New: `assets/js/condition_builder/condition_group.js`

### Implementation Steps

**4.1. Module structure**

```javascript
/**
 * Renders a condition group — a set of blocks wrapped together.
 *
 * Groups have a colored left border, their own AND/OR toggle, and
 * inner block cards rendered via createConditionBlock. Max nesting:
 * one level (groups cannot contain groups).
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - Group container element
 * @param {Object} opts.group - Group data {id, type, logic, blocks}
 * @param {Array} opts.variables - All project variables
 * @param {Array} opts.sheetsWithVariables - Grouped sheets
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {boolean} opts.switchMode - Whether in switch mode
 * @param {Object} opts.translations - Translated strings
 * @param {Function} opts.onChange - Callback when group changes: (updatedGroup) => void
 * @param {Function} opts.onUngroup - Callback to dissolve group: () => void
 * @returns {{ getGroup: Function, destroy: Function }}
 */
export function createConditionGroup(opts) { ... }
```

**4.2. Rendering logic**

- Outer container: `div.condition-group` with a colored left border (e.g., `border-l-4 border-primary/30`), rounded corners, padding
- Header row: AND/OR toggle for the group (same pattern as block toggle)
- For each inner block: create a `div` and call `createConditionBlock(...)` -- blocks inside groups do NOT have remove buttons (removing a block from a group is done by ungrouping)
- Footer: "Add block" button (creates empty block inside the group) + "Ungroup" button
- The "Ungroup" button calls `opts.onUngroup()`, which the parent builder handles by dissolving the group into its constituent blocks at the same level

**4.3. Callback wiring**

- When an inner block changes, update the group's blocks array and call `opts.onChange(updatedGroup)`
- When a block is removed from inside the group, splice and call `opts.onChange`
- Logic toggle updates `group.logic`
- "Add block" creates a new empty block `{id, type: "block", logic: "all", rules: []}`

**4.4. Public API**

```javascript
return {
  getGroup: () => ({ ...currentGroup, blocks: currentGroup.blocks.map(b => ({...b})) }),
  destroy: () => { destroyBlocks(); container.innerHTML = ""; }
};
```

### Test Battery

Manual integration testing:

- Verify group renders with colored left border
- Verify AND/OR toggle inside group works
- Verify "Add block" inside group adds a new empty block card
- Verify "Ungroup" dissolves the group into separate blocks at top level
- Verify read-only mode hides all edit controls

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 5: Refactor `condition_builder_core.js` for Block-Based Rendering

### Description

Refactor the core builder to render blocks and groups instead of a flat rule list. This is the largest JS change. The builder becomes a container of blocks and groups, with a top-level AND/OR toggle and a selection mode for grouping.

### Files Affected

- `assets/js/screenplay/builders/condition_builder_core.js` -- major refactor

### Implementation Steps

**5.1. Detect format and auto-upgrade**

On initialization, check if `currentCondition` has `blocks` or `rules`. If `rules` (old format), convert to block format:

```javascript
function ensureBlockFormat(condition) {
  if (condition.blocks) return condition;
  // Old format: wrap rules in a single block
  const rules = condition.rules || [];
  return {
    logic: "all",
    blocks: rules.length > 0 ? [{
      id: `block_${Date.now()}`,
      type: "block",
      logic: condition.logic || "all",
      rules: rules
    }] : []
  };
}
```

Always work internally with the block format. On push to server, send whatever format we have (the backend handles both).

**5.2. Replace flat-rule rendering with block/group rendering**

Replace the current `render()` function. Instead of iterating `currentCondition.rules` and calling `createConditionRuleRow`, iterate `currentCondition.blocks` and dispatch:

```javascript
function render() {
  destroyItems();
  container.innerHTML = "";

  const blocks = currentCondition.blocks || [];

  // Top-level logic toggle (when 2+ blocks AND not in switch mode)
  if (blocks.length >= 2 && !switchMode) {
    container.appendChild(renderTopLogicToggle());
  }

  // Render blocks and groups
  const itemsContainer = document.createElement("div");
  itemsContainer.className = "space-y-2";
  container.appendChild(itemsContainer);

  blocks.forEach((block, index) => {
    const itemEl = document.createElement("div");
    itemsContainer.appendChild(itemEl);

    if (block.type === "group") {
      const groupInstance = createConditionGroup({
        container: itemEl,
        group: block,
        variables, sheetsWithVariables, canEdit, switchMode,
        translations: t,
        onChange: (updatedGroup) => {
          currentCondition.blocks[index] = updatedGroup;
          push();
        },
        onUngroup: () => {
          // Replace group with its inner blocks at this position
          const innerBlocks = block.blocks || [];
          currentCondition.blocks.splice(index, 1, ...innerBlocks);
          push();
          render();
        }
      });
      items.push(groupInstance);
    } else {
      const blockInstance = createConditionBlock({
        container: itemEl,
        block: block,
        variables, sheetsWithVariables, canEdit, switchMode,
        translations: t,
        onChange: (updatedBlock) => {
          currentCondition.blocks[index] = updatedBlock;
          push();
        },
        onRemove: () => {
          currentCondition.blocks.splice(index, 1);
          push();
          render();
        }
      });
      items.push(blockInstance);
    }
  });

  // Bottom action bar
  if (canEdit) {
    const actionBar = document.createElement("div");
    actionBar.className = "flex gap-2 mt-2";

    // Add block button
    const addBlockBtn = createAddBlockButton();
    actionBar.appendChild(addBlockBtn);

    // Group button (only when 2+ blocks exist)
    if (blocks.length >= 2) {
      const groupBtn = createGroupButton();
      actionBar.appendChild(groupBtn);
    }

    container.appendChild(actionBar);
  }
}
```

**5.3. Selection mode for grouping**

Add state variables `selectionMode` (boolean) and `selectedBlockIds` (Set).

When user clicks "Group":
1. Set `selectionMode = true`, `selectedBlockIds = new Set()`
2. Re-render: all blocks become non-editable, checkboxes appear on each block
3. User clicks checkboxes to select 2+ blocks
4. "Group selected (N)" button activates when N >= 2
5. On click: remove selected blocks from `currentCondition.blocks`, wrap them in a new group, insert the group at the position of the first selected block
6. Exit selection mode, push, re-render

```javascript
function enterSelectionMode() {
  selectionMode = true;
  selectedBlockIds.clear();
  render();
}

function exitSelectionMode() {
  selectionMode = false;
  selectedBlockIds.clear();
  render();
}

function groupSelectedBlocks() {
  const selectedIndices = [];
  currentCondition.blocks.forEach((block, i) => {
    if (selectedBlockIds.has(block.id)) selectedIndices.push(i);
  });

  if (selectedIndices.length < 2) return;

  const blocksToGroup = selectedIndices.map(i => currentCondition.blocks[i]);
  // Only blocks can be grouped, not groups (groups cannot contain groups)
  const validBlocks = blocksToGroup.filter(b => b.type === "block");
  if (validBlocks.length < 2) return;

  const newGroup = {
    id: `group_${Date.now()}`,
    type: "group",
    logic: "all",
    blocks: validBlocks
  };

  // Remove selected blocks and insert group at first position
  const insertAt = selectedIndices[0];
  currentCondition.blocks = currentCondition.blocks.filter((_, i) => !selectedIndices.includes(i));
  currentCondition.blocks.splice(insertAt, 0, newGroup);

  exitSelectionMode();
  push();
  render();
}
```

**5.4. Update the top-level logic toggle**

Rename `renderLogicToggle()` to `renderTopLogicToggle()`. It now toggles `currentCondition.logic` at the top level (between blocks), not between rules. The text changes from "Match all/any of the rules" to "Match all/any of these blocks" (new translation key).

**5.5. Update `update(newCondition)` to handle both formats**

```javascript
update(newCondition) {
  currentCondition = ensureBlockFormat(newCondition || { logic: "all", rules: [] });
  render();
}
```

**5.6. Add new translation keys**

The translations object gains:
- `add_block`: "Add block"
- `group`: "Group"
- `group_selected`: "Group selected"
- `cancel`: "Cancel"
- `ungroup`: "Ungroup"
- `of_the_blocks`: "of these blocks"

### Test Battery

Manual integration testing:

- Verify old flat-rules condition auto-upgrades to block format on load
- Verify single block renders identically to the old flat-rule view
- Verify adding a second block renders two block cards
- Verify top-level AND/OR toggle appears when 2+ blocks
- Verify selection mode activates on "Group" button click
- Verify 2+ blocks can be selected and grouped
- Verify group appears with colored border, inner blocks, ungroup button
- Verify "Ungroup" dissolves group back to separate blocks
- Verify pushEvent sends the correct block-based JSON to the server
- Verify collaboration updates via `node_updated` handle block format
- Verify switch mode still works (each block gets label input)

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 6: HEEx Component + Hook Integration

### Description

Update the HEEx `condition_builder.ex` component and the `condition_builder.js` hook to pass through the new block-based format. Add new translation keys. Ensure the condition node sidebar and dialogue response conditions continue working without changes.

### Files Affected

- `lib/storyarn_web/components/condition_builder.ex` -- add new translations, handle block format in `parsed_condition`
- `assets/js/hooks/condition_builder.js` -- handle block format in collaboration updates

### Implementation Steps

**6.1. Update `condition_builder.ex` parsed_condition**

The component currently only matches `%{"logic" => _, "rules" => _}`. Add a match for blocks:

```elixir
def condition_builder(assigns) do
  parsed_condition =
    case assigns.condition do
      nil -> Condition.new()
      %{"logic" => _, "blocks" => _} = cond -> cond
      %{"logic" => _, "rules" => _} = cond -> cond
      :legacy -> Condition.new()
      _string -> Condition.new()
    end
  # ... rest unchanged
end
```

**6.2. Add new translation keys to `translations/0`**

```elixir
def translations do
  %{
    # ... existing keys ...
    add_block: dgettext("flows", "Add block"),
    group: dgettext("flows", "Group"),
    group_selected: dgettext("flows", "Group selected"),
    cancel: dgettext("flows", "Cancel"),
    ungroup: dgettext("flows", "Ungroup"),
    of_the_blocks: dgettext("flows", "of these blocks")
  }
end
```

**6.3. Update `condition_builder.js` hook collaboration handler**

The `handleEvent("node_updated", ...)` handler currently checks `data.data?.condition`. Block-format conditions stored in node data may have `blocks` instead of `rules`. The existing `deepEqual` comparison handles this automatically. No code change needed -- just verify it works.

**6.4. Verify condition node handlers in show.ex**

The `"update_condition_builder"` event handler in `show.ex` receives the full condition map from the JS hook and passes it to `Condition.Node.handle_update_condition_builder/2`, which calls `Condition.sanitize/1` on it. Since we extended `sanitize/1` in Subtask 1 to handle blocks, this works automatically. Verify end-to-end:

1. Open a condition node
2. Condition builder renders
3. Add blocks, group them
4. Each change pushes to server
5. Server sanitizes and persists
6. Collaboration broadcast sends block format
7. Other users see the block-based condition

**6.5. Gettext extraction**

Run `mix gettext.extract --merge` to add the new translation keys to the PO files.

### Test Battery

Add to `test/storyarn_web/live/flow_live/show_events_test.exs`:

```elixir
describe "condition builder integration" do
  test "sanitize/1 handles block-based condition from JS hook" do
    input = %{
      "logic" => "any",
      "blocks" => [
        %{"id" => "b1", "type" => "block", "logic" => "all",
          "rules" => [%{"id" => "r1", "sheet" => "mc", "variable" => "hp",
                        "operator" => "equals", "value" => "10", "extra_key" => "bad"}]},
        %{"id" => "g1", "type" => "group", "logic" => "all",
          "blocks" => [
            %{"id" => "b2", "type" => "block", "logic" => "all",
              "rules" => [%{"id" => "r2", "sheet" => "g", "variable" => "q",
                            "operator" => "is_true"}]}
          ]}
      ]
    }

    result = Condition.sanitize(input)
    assert result["logic"] == "any"
    assert length(result["blocks"]) == 2

    [block, group] = result["blocks"]
    assert block["type"] == "block"
    assert group["type"] == "group"

    # extra_key should be stripped from rule
    rule = hd(block["rules"])
    refute Map.has_key?(rule, "extra_key")
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 7: End-to-End Verification and Edge Cases

### Description

Final integration pass to verify the full pipeline: condition builder UI -> hook -> server sanitize -> DB persist -> evaluate -> Story Player/debugger. Handle edge cases and add comprehensive integration tests.

### Files Affected

- `test/storyarn/flows/condition_test.exs` -- edge case tests
- `test/storyarn/flows/evaluator/condition_eval_test.exs` -- integration tests
- `lib/storyarn/flows/condition.ex` -- any fixes discovered during testing

### Implementation Steps

**7.1. Verify evaluate_string/2 with block format**

`evaluate_string/2` calls `Condition.parse/1` first. Since `parse/1` now handles blocks, this should work. Add a test:

```elixir
test "evaluate_string/2 with block format JSON" do
  variables = %{
    "mc.jaime.health" => var(80, "number"),
    "mc.jaime.alive" => var(true, "boolean")
  }

  json = Jason.encode!(%{
    "logic" => "all",
    "blocks" => [
      %{"id" => "b1", "type" => "block", "logic" => "all",
        "rules" => [%{"id" => "r1", "sheet" => "mc.jaime", "variable" => "health",
                      "operator" => "greater_than", "value" => "50"}]},
      %{"id" => "b2", "type" => "block", "logic" => "all",
        "rules" => [%{"id" => "r2", "sheet" => "mc.jaime", "variable" => "alive",
                      "operator" => "is_true"}]}
    ]
  })

  assert {true, results} = ConditionEval.evaluate_string(json, variables)
  assert length(results) == 2
end
```

**7.2. Verify Story Player compatibility**

The Story Player uses `ConditionEval.evaluate/2` through `ConditionNodeEvaluator` and `DialogueEvaluator`. Trace the call chain:
- `ConditionNodeEvaluator.evaluate/3` calls `ConditionEval.evaluate/2` -- works with both formats
- `DialogueEvaluator.evaluate_responses/2` calls `ConditionEval.evaluate_string/2` for response conditions -- works with both formats

No code changes needed, but add a test that simulates the full chain.

**7.3. Edge case: switch mode with blocks**

In switch mode, each rule gets a label. With blocks, labels should be per-block (the first rule's label, or a block-level label). This is a design decision. For now, switch mode continues to work with blocks -- each block's rules can have labels. The condition node switch mode already renders rule labels via `condition_rule_row.js`, which is unchanged.

Verify: condition node in switch mode with block-based conditions still shows labels and creates output pins correctly.

**7.4. Edge case: upgrade then downgrade**

If a user edits a block-based condition and then somehow the condition is loaded by old code (e.g., during rollback), the old `parse/1` will return `:legacy` for a JSON with `blocks`. This is acceptable -- legacy conditions pass automatically. Document this in the module doc.

**7.5. Edge case: empty groups**

A group with zero inner blocks should be treated as a no-op (evaluates to true). Verify `evaluate_block/2` handles this.

### Test Battery

Consolidation of edge case tests in existing test files:

```elixir
# In condition_eval_test.exs:
describe "block format edge cases" do
  test "block with empty rules evaluates to true"
  test "group with empty blocks evaluates to true"
  test "group with one block behaves same as standalone block"
  test "deeply nested group (group in group) is rejected by sanitize — flattened"
  test "mixed format: condition with both 'rules' and 'blocks' keys — blocks take precedence"
end

# In condition_test.exs:
describe "edge cases" do
  test "sanitize rejects group containing a group (only blocks allowed in groups)"
  test "parse handles malformed block type gracefully"
  test "to_json with block containing rules with labels preserves labels"
  test "upgrade preserves rule labels for switch mode"
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary of All Files Affected

### Backend (Elixir)

| File                                               | Change Type                                            |
|----------------------------------------------------|--------------------------------------------------------|
| `lib/storyarn/flows/condition.ex`                  | Modified -- new format support in all public functions |
| `lib/storyarn/flows/evaluator/condition_eval.ex`   | Modified -- recursive block evaluation                 |
| `lib/storyarn_web/components/condition_builder.ex` | Modified -- block format passthrough, new translations |

### Frontend (JavaScript)

| File                                                          | Change Type                                       |
|---------------------------------------------------------------|---------------------------------------------------|
| `assets/js/condition_builder/condition_block.js`              | New -- block card component                       |
| `assets/js/condition_builder/condition_group.js`              | New -- group wrapper component                    |
| `assets/js/screenplay/builders/condition_builder_core.js`     | Modified -- block-based rendering, selection mode |
| `assets/js/hooks/condition_builder.js`                        | Minor -- verify block format in collaboration     |
| `assets/js/condition_builder/condition_rule_row.js`           | Unchanged                                         |
| `assets/js/condition_builder/condition_sentence_templates.js` | Unchanged                                         |

### Tests

| File                                                    | Change Type                                   |
|---------------------------------------------------------|-----------------------------------------------|
| `test/storyarn/flows/condition_test.exs`                | New -- comprehensive tests for `condition.ex` |
| `test/storyarn/flows/evaluator/condition_eval_test.exs` | Modified -- block/group evaluation tests      |
| `test/storyarn_web/live/flow_live/show_events_test.exs` | Modified -- sanitization integration test     |

### Gettext

| File                                   | Change Type                      |
|----------------------------------------|----------------------------------|
| `priv/gettext/en/LC_MESSAGES/flows.po` | Modified -- new translation keys |
| `priv/gettext/es/LC_MESSAGES/flows.po` | Modified -- new translation keys |

---

**Next:** [`02_CREATE_LINKED_FLOW.md`](./02_CREATE_LINKED_FLOW.md)
