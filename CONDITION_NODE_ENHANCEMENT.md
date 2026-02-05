# Condition Node Enhancement Plan

> **Objective**: Transform the Condition node from a simple string-matching switch into a powerful, variable-aware routing system that integrates with Storyarn's page variable system.

> **Related Documents**:
> - [Research: Condition Placement](./docs/research/DIALOGUE_CONDITIONS_RESEARCH.md)
> - [Recommendations: Condition Model](./docs/DIALOGUE_CONDITIONS_RECOMMENDATIONS.md)
> - [Dialogue Enhancement](./DIALOGUE_NODE_ENHANCEMENT.md)

---

## Executive Summary

The current Condition node is a **simple string switch** that doesn't integrate with Storyarn's variable system. This document proposes enhancing it to:

1. **Evaluate conditions using page variables** (blocks as variables)
2. **Support complex expressions** with multiple rules and logic operators
3. **Provide visual condition building** (reuse existing ConditionBuilder)
4. **Offer expression mode** for advanced users
5. **Export evaluable conditions** for game engines

---

## Current State

### Condition Node Data Structure

```elixir
# lib/storyarn_web/live/flow_live/components/node_type_helpers.ex
def default_node_data("condition") do
  %{
    "expression" => "",           # Just a string - NOT evaluated
    "cases" => [
      %{"id" => "case_true", "value" => "true", "label" => "True"},
      %{"id" => "case_false", "value" => "false", "label" => "False"}
    ]
  }
end
```

### Problems

| Issue                           | Description                                                            |
|---------------------------------|------------------------------------------------------------------------|
| **No variable integration**     | `expression` is just a display string, not connected to page variables |
| **No evaluation logic**         | Cases match string values, no actual condition evaluation              |
| **Disconnected from responses** | Response conditions use ConditionBuilder, but Condition node doesn't   |
| **Limited use cases**           | Can only do simple string matching, not real game logic                |

### What Works (Keep)

| Feature                    | Status   | Notes                            |
|----------------------------|----------|----------------------------------|
| Multi-output cases         | ✅ Keep   | Good pattern for routing         |
| Dynamic outputs on canvas  | ✅ Keep   | Cases render as separate outputs |
| Case add/remove UI         | ✅ Keep   | Works well                       |
| Default case (empty value) | ✅ Keep   | Fallback routing                 |

---

## Page Variables System

Storyarn already has a robust variable system based on **Page Blocks**:

### How Variables Work

```
Page (shortcut: "mc.jaime")
├── Block: "Name" (text, is_constant: true)      → NOT a variable
├── Block: "Health" (number, is_constant: false) → Variable: mc.jaime.health
├── Block: "Class" (select, is_constant: false)  → Variable: mc.jaime.class
└── Block: "Alive" (boolean, is_constant: false) → Variable: mc.jaime.alive
```

### Variable Discovery

```elixir
# lib/storyarn/pages/page_crud.ex
def list_project_variables(project_id) do
  # Returns all blocks where:
  # - is_constant == false
  # - type is variable-capable (text, number, select, boolean, date, etc.)
  # - has a variable_name set
end

# Returns:
[
  %{
    page_id: 1,
    page_name: "Jaime",
    page_shortcut: "mc.jaime",
    block_id: 5,
    variable_name: "health",
    block_type: "number",
    options: nil
  },
  %{
    page_id: 1,
    page_name: "Jaime",
    page_shortcut: "mc.jaime",
    block_id: 6,
    variable_name: "class",
    block_type: "select",
    options: ["warrior", "mage", "rogue"]
  }
]
```

### Existing Condition Builder

The `ConditionBuilder` component (used for response conditions) already supports:

```elixir
# Condition structure
%{
  "logic" => "all",  # "all" (AND) or "any" (OR)
  "rules" => [
    %{
      "page" => "mc.jaime",
      "variable" => "class",
      "operator" => "equals",
      "value" => "warrior"
    },
    %{
      "page" => "mc.jaime",
      "variable" => "health",
      "operator" => "greater_than",
      "value" => "50"
    }
  ]
}
```

**Operators by type:**

| Block Type   | Operators                                                                              |
|--------------|----------------------------------------------------------------------------------------|
| text         | equals, not_equals, contains, starts_with, ends_with, is_empty                         |
| number       | equals, not_equals, greater_than, greater_than_or_equal, less_than, less_than_or_equal |
| boolean      | is_true, is_false, is_nil                                                              |
| select       | equals, not_equals, is_nil                                                             |
| multi_select | contains, not_contains, is_empty                                                       |
| date         | equals, not_equals, before, after                                                      |

---

## Proposed Enhancement

### New Data Structure

```elixir
def default_node_data("condition") do
  %{
    # === PRIMARY CONDITION ===
    "condition" => %{
      "logic" => "all",
      "rules" => []
    },

    # === EXPRESSION MODE (optional) ===
    "expression" => "",           # Raw expression for advanced users
    "mode" => "builder",          # "builder" | "expression"

    # === ROUTING CASES ===
    "cases" => [
      %{
        "id" => "case_true",
        "type" => "match",        # "match" | "condition"
        "value" => "true",        # For type: "match"
        "condition" => nil,       # For type: "condition" (future)
        "label" => "True"
      },
      %{
        "id" => "case_false",
        "type" => "match",
        "value" => "false",
        "condition" => nil,
        "label" => "False"
      }
    ],

    # === EVALUATION RESULT ===
    "result_variable" => ""       # Optional: store result in a variable
  }
end
```

### Node Types

The enhancement introduces **three condition node patterns**:

#### Pattern A: Boolean Gate (if/else)

Evaluates a condition and routes to True or False.

```
┌─────────────────────────────────┐
│ ⑂ Condition                     │
├─────────────────────────────────┤
│ IF mc.jaime.health > 50         │
│ AND mc.jaime.class == "warrior" │
├─────────────────────────────────┤
│ ○───────────────────────────────│
│                       True  ──○ │
│                      False  ──○ │
└─────────────────────────────────┘
```

**Use case**: Simple branching based on game state.

#### Pattern B: Switch/Case (value matching)

Evaluates a variable and routes based on its value.

```
┌─────────────────────────────────┐
│ ⑂ mc.jaime.class                │
├─────────────────────────────────┤
│ SWITCH ON: Class                │
├─────────────────────────────────┤
│ ○───────────────────────────────│
│                   "warrior" ──○ │
│                      "mage" ──○ │
│                     "rogue" ──○ │
│                   (default) ──○ │
└─────────────────────────────────┘
```

**Use case**: Multi-path routing based on a single variable.

#### Pattern C: Multi-Condition (advanced)

Each case has its own condition (first match wins).

```
┌─────────────────────────────────┐
│ ⑂ Combat Check                  │
├─────────────────────────────────┤
│ FIRST MATCH WINS                │
├─────────────────────────────────┤
│ ○───────────────────────────────│
│     health <= 0: "Dead"     ──○ │
│   health < 25: "Critical"   ──○ │
│    health < 50: "Wounded"   ──○ │
│            else: "Healthy"  ──○ │
└─────────────────────────────────┘
```

**Use case**: Complex state machines, priority-based routing.

---

## Implementation Phases

### Phase 1: Variable Integration (Essential)
**Effort: Medium | Priority: High**

Integrate page variables into the Condition node using the existing ConditionBuilder.

#### 1.1 Reuse ConditionBuilder Component

The ConditionBuilder already exists for response conditions. Reuse it in the Condition node properties panel.

**Changes to properties_panels.ex:**

```heex
<%!-- Condition node properties panel --%>
<div class="space-y-4">
  <%!-- Mode toggle --%>
  <div class="flex gap-2">
    <button
      phx-click="set_condition_mode"
      phx-value-mode="builder"
      class={["btn btn-sm", @node.data["mode"] == "builder" && "btn-primary"]}
    >
      Visual Builder
    </button>
    <button
      phx-click="set_condition_mode"
      phx-value-mode="expression"
      class={["btn btn-sm", @node.data["mode"] == "expression" && "btn-primary"]}
    >
      Expression
    </button>
  </div>

  <%!-- Visual builder mode --%>
  <%= if @node.data["mode"] != "expression" do %>
    <.condition_builder
      condition={@node.data["condition"]}
      project_variables={@project_variables}
      on_change="update_node_condition"
      id={"condition-builder-#{@node.id}"}
    />
  <% else %>
    <%!-- Expression mode --%>
    <textarea
      phx-blur="update_node_field"
      phx-value-field="expression"
      class="textarea textarea-bordered w-full font-mono"
      placeholder="mc.jaime.health > 50 && mc.jaime.class == 'warrior'"
    ><%= @node.data["expression"] %></textarea>
  <% end %>

  <%!-- Cases section (existing) --%>
  <.condition_cases_form cases={@node.data["cases"]} ... />
</div>
```

#### 1.2 Update Default Data

```elixir
def default_node_data("condition") do
  %{
    "condition" => %{"logic" => "all", "rules" => []},
    "expression" => "",
    "mode" => "builder",
    "cases" => [
      %{"id" => generate_id(), "type" => "match", "value" => "true", "label" => "True"},
      %{"id" => generate_id(), "type" => "match", "value" => "false", "label" => "False"}
    ]
  }
end
```

#### 1.3 Event Handlers

```elixir
# In flow_live/show.ex
def handle_event("update_node_condition", %{"condition" => condition}, socket) do
  update_node_field(socket, "condition", condition)
end

def handle_event("set_condition_mode", %{"mode" => mode}, socket) do
  update_node_field(socket, "mode", mode)
end
```

#### Tasks
- [ ] Add `condition` field to condition node default data
- [ ] Add `mode` field ("builder" | "expression")
- [ ] Integrate ConditionBuilder component into condition properties panel
- [ ] Add mode toggle UI (Visual Builder / Expression)
- [ ] Handle `update_node_condition` event
- [ ] Update canvas node preview to show condition summary

---

### Phase 2: Switch Mode (Variable Matching)
**Effort: Medium | Priority: High**

Add a "switch" mode that evaluates a single variable and routes based on value.

#### 2.1 New Fields

```elixir
%{
  # ... existing fields ...
  "switch_mode" => false,          # Enable switch mode
  "switch_variable" => %{          # Variable to switch on
    "page" => "",
    "variable" => ""
  }
}
```

#### 2.2 UI Updates

When switch_mode is enabled:
- Show variable selector (page + variable dropdowns)
- Cases become value matchers for that variable
- Auto-populate cases from select options if variable is a select type

```
┌─────────────────────────────────────┐
│ ⑂ Condition                      ✕ │
├─────────────────────────────────────┤
│                                     │
│ [x] Switch Mode                     │
│                                     │
│ Variable   [mc.jaime ▼] [class ▼]   │
│                                     │
│ ─────────── Cases ────────────────  │
│                                     │
│ [Auto-populate from options]        │
│                                     │
│ ┌─ Case 1 ────────────────────────┐ │
│ │ Value: [warrior    ]            │ │
│ │ Label: [Warrior    ]            │ │
│ └─────────────────────────────────┘ │
│ ...                                 │
└─────────────────────────────────────┘
```

#### 2.3 Auto-Populate Cases

When selecting a `select` or `multi_select` variable:

```elixir
def auto_populate_cases(variable_info) do
  case variable_info.options do
    nil ->
      # Keep existing cases
      nil
    options when is_list(options) ->
      # Generate cases from options
      cases = Enum.map(options, fn option ->
        %{
          "id" => generate_id(),
          "type" => "match",
          "value" => option,
          "label" => humanize(option)
        }
      end)
      # Add default case
      cases ++ [%{"id" => generate_id(), "type" => "match", "value" => "", "label" => "Default"}]
  end
end
```

#### Tasks
- [ ] Add `switch_mode` and `switch_variable` fields
- [ ] Create switch mode toggle in properties panel
- [ ] Add variable selector (page + variable dropdowns)
- [ ] Implement auto-populate cases from select options
- [ ] Update canvas preview for switch mode
- [ ] Handle variable type changes (re-populate cases)

---

### Phase 3: Canvas Visualization
**Effort: Low-Medium | Priority: Medium**

Improve how condition nodes display on canvas.

#### 3.1 Condition Summary

Show a human-readable summary of the condition:

```javascript
// storyarn_node.js
function getConditionSummary(nodeData) {
  if (nodeData.switch_mode && nodeData.switch_variable?.variable) {
    return `SWITCH: ${nodeData.switch_variable.page}.${nodeData.switch_variable.variable}`;
  }

  if (nodeData.mode === "expression" && nodeData.expression) {
    return truncate(nodeData.expression, 40);
  }

  if (nodeData.condition?.rules?.length > 0) {
    const rules = nodeData.condition.rules;
    const logic = nodeData.condition.logic === "all" ? "AND" : "OR";

    if (rules.length === 1) {
      return formatRule(rules[0]);
    }
    return `${rules.length} rules (${logic})`;
  }

  return "No condition set";
}

function formatRule(rule) {
  // "mc.jaime.health > 50"
  return `${rule.page}.${rule.variable} ${operatorSymbol(rule.operator)} ${rule.value}`;
}
```

#### 3.2 Visual Indicators

| Indicator   |  Meaning                   |
|-------------|----------------------------|
| 🔀          | Switch mode enabled        |
| 📝          | Expression mode (raw text) |
| (none)      | Visual builder mode        |

#### 3.3 Node Header Updates

```
Normal mode:
┌─────────────────────────────────┐
│ ⑂ mc.jaime.health > 50          │  ← Condition summary

Switch mode:
┌─────────────────────────────────┐
│ ⑂🔀 mc.jaime.class              │  ← Switch indicator + variable

Expression mode:
┌─────────────────────────────────┐
│ ⑂📝 health > 50 && alive        │  ← Expression indicator + text
```

#### Tasks
- [ ] Create `getConditionSummary()` function in JS
- [ ] Update node header to show condition summary
- [ ] Add mode indicators (🔀 📝)
- [ ] Handle long conditions with truncation + tooltip
- [ ] Style improvements for condition nodes

---

### Phase 4: Expression Language
**Effort: High | Priority: Low (defer)**

Define and implement a proper expression language for advanced users.

> **Note**: This phase can be deferred. The visual builder covers most use cases. Expression mode can initially just store raw text for export.

#### 4.1 Syntax Definition

```javascript
// Variables
mc.jaime.health           // Page shortcut + variable name
player.gold
world.time_of_day

// Comparisons
mc.jaime.health > 50
mc.jaime.class == "warrior"
player.name != "Guard"

// Logical operators
mc.jaime.health > 50 && mc.jaime.class == "warrior"
player.gold >= 100 || player.has_discount
!mc.jaime.alive

// Functions (future)
has_item("key")
visited("tavern")
quest_active("main_quest")

// Grouping
(player.gold >= 50 && has_item("map")) || player.is_vip
```

#### 4.2 Parser (Future)

```elixir
defmodule Storyarn.Conditions.Parser do
  @moduledoc """
  Parses expression strings into structured conditions.
  """

  def parse(expression) when is_binary(expression) do
    # Tokenize and parse expression
    # Return {:ok, condition} or {:error, reason}
  end
end
```

#### 4.3 Validator

```elixir
defmodule Storyarn.Conditions.Validator do
  @moduledoc """
  Validates conditions against project variables.
  """

  def validate(condition, project_variables) do
    # Check all referenced variables exist
    # Check operators are valid for variable types
    # Return {:ok, condition} or {:error, errors}
  end
end
```

#### Tasks (Deferred)
- [ ] Define expression grammar
- [ ] Implement tokenizer
- [ ] Implement parser
- [ ] Implement validator
- [ ] Add syntax highlighting in expression textarea
- [ ] Add autocomplete for variable names
- [ ] Add error highlighting for invalid expressions

---

### Phase 5: Export Format
**Effort: Medium | Priority: Medium**

Ensure conditions export in a format game engines can evaluate.

#### 5.1 Export Structure

```json
{
  "nodes": [
    {
      "id": "condition_1",
      "type": "condition",
      "data": {
        "mode": "builder",
        "condition": {
          "logic": "all",
          "rules": [
            {
              "variable": "mc.jaime.health",
              "operator": "greater_than",
              "value": 50
            },
            {
              "variable": "mc.jaime.class",
              "operator": "equals",
              "value": "warrior"
            }
          ]
        },
        "expression": "mc.jaime.health > 50 && mc.jaime.class == 'warrior'",
        "cases": [
          {"id": "case_true", "value": "true", "label": "True"},
          {"id": "case_false", "value": "false", "label": "False"}
        ]
      }
    }
  ]
}
```

#### 5.2 Evaluation Pseudocode (for game engines)

```javascript
// Example evaluation in a game engine
function evaluateCondition(condition, gameState) {
  const rules = condition.rules;
  const logic = condition.logic;

  const results = rules.map(rule => {
    const value = getVariable(gameState, rule.variable);
    return evaluateOperator(value, rule.operator, rule.value);
  });

  if (logic === "all") {
    return results.every(r => r);  // AND
  } else {
    return results.some(r => r);   // OR
  }
}

function getVariable(gameState, path) {
  // "mc.jaime.health" → gameState.variables["mc.jaime"]["health"]
  const [page, variable] = path.split(".");
  return gameState.variables[page]?.[variable];
}
```

#### 5.3 Expression Export

When mode is "expression", also export the parsed condition (if valid):

```json
{
  "mode": "expression",
  "expression": "mc.jaime.health > 50 && mc.jaime.alive",
  "parsed_condition": {
    "logic": "all",
    "rules": [...]
  }
}
```

#### Tasks
- [ ] Update flow export to include full condition data
- [ ] Document condition evaluation algorithm
- [ ] Export both builder and expression formats
- [ ] Validate conditions before export
- [ ] Generate expression string from builder conditions

---

## Files to Modify

### Backend (Elixir)

| File                                                              | Changes                                  |
|-------------------------------------------------------------------|------------------------------------------|
| `lib/storyarn_web/live/flow_live/components/node_type_helpers.ex` | Update default_node_data for condition   |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex` | Add condition builder to condition panel |
| `lib/storyarn_web/live/flow_live/show.ex`                         | Handle new condition events              |
| `lib/storyarn_web/components/condition_builder.ex`                | Minor updates if needed                  |
| `lib/storyarn/pages/page_crud.ex`                                 | Ensure list_project_variables works      |

### Frontend (JavaScript)

| File                                                      | Changes                      |
|-----------------------------------------------------------|------------------------------|
| `assets/js/hooks/flow_canvas/components/storyarn_node.js` | Condition summary display    |
| `assets/js/hooks/flow_canvas/node_config.js`              | Update condition node config |

### Styles (CSS)

| File                 | Changes                |
|----------------------|------------------------|
| `assets/css/app.css` | Condition node styling |

---

## Migration

### Existing Condition Nodes

Existing condition nodes with the old structure will continue to work:

```elixir
def normalize_condition_data(data) do
  # Add new fields with defaults if missing
  data
  |> Map.put_new("condition", %{"logic" => "all", "rules" => []})
  |> Map.put_new("mode", "builder")
  |> Map.put_new("switch_mode", false)
  |> Map.put_new("switch_variable", %{"page" => "", "variable" => ""})
  |> normalize_cases()
end

defp normalize_cases(%{"cases" => cases} = data) when is_list(cases) do
  # Add "type" field to existing cases
  updated_cases = Enum.map(cases, fn case ->
    Map.put_new(case, "type", "match")
  end)
  Map.put(data, "cases", updated_cases)
end
```

---

## Testing Checklist

### Phase 1 (Variable Integration)
- [ ] Condition builder renders in condition node panel
- [ ] Can add rules with page/variable/operator/value
- [ ] Can switch between AND/OR logic
- [ ] Conditions persist on save
- [ ] Mode toggle switches between builder and expression
- [ ] Expression text saves correctly

### Phase 2 (Switch Mode)
- [ ] Switch mode toggle works
- [ ] Variable selector shows project variables
- [ ] Selecting select-type variable auto-populates cases
- [ ] Cases update when variable changes
- [ ] Default case always present
- [ ] Canvas shows switch mode indicator

### Phase 3 (Canvas Visualization)
- [ ] Condition summary shows in node header
- [ ] Long conditions truncate with tooltip
- [ ] Mode indicators display correctly
- [ ] Switch mode shows variable name

### Phase 4 (Expression Language)
- [ ] Expression syntax is documented
- [ ] Parser handles basic expressions
- [ ] Validator catches invalid variables
- [ ] Autocomplete works (if implemented)

### Phase 5 (Export)
- [ ] Export includes full condition data
- [ ] Both modes export correctly
- [ ] Expression generates from builder conditions
- [ ] Validation errors prevent export

---

## Summary

| Phase   | Priority   | Effort   | Description                                |
|---------|------------|----------|--------------------------------------------|
| 1       | High       | Medium   | Variable integration with ConditionBuilder |
| 2       | High       | Medium   | Switch mode for single-variable routing    |
| 3       | Medium     | Low      | Canvas visualization improvements          |
| 4       | Low        | High     | Expression language (defer)                |
| 5       | Medium     | Medium   | Export format and documentation            |

**Recommended order**: 1 → 2 → 3 → 5 → 4 (defer phase 4)

The visual builder (Phase 1-2) covers 90% of use cases. Expression mode can start as "raw text for export" and be enhanced later with parsing/validation.
