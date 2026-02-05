# Condition Node Enhancement

> **Status**: Phase 1-2 Complete
> **Last Updated**: 2026-02-05

---

## Overview

The Condition node evaluates conditions using Storyarn's page variable system and routes flow based on results.

### Two Modes

| Mode | Description | Outputs |
|------|-------------|---------|
| **Condition** (default) | Evaluates all rules with AND/OR logic | True / False |
| **Switch** | Each rule is independent, first match wins | One per rule + Default |

---

## Data Structure

```elixir
def default_node_data("condition") do
  %{
    "condition" => %{"logic" => "all", "rules" => []},
    "switch_mode" => false
  }
end
```

### Rule Structure

```elixir
%{
  "id" => "rule_123",
  "page" => "mc.jaime",        # Page shortcut
  "variable" => "health",       # Variable name
  "operator" => "greater_than", # Comparison operator
  "value" => "50",              # Value to compare
  "label" => "Healthy"          # Output label (switch mode only)
}
```

---

## Condition Mode (Default)

Evaluates all rules together using AND/OR logic.

```
┌─────────────────────────────────────┐
│ ⑂ Condition                         │
├─────────────────────────────────────┤
│ mc.jaime.health > 50                │
├─────────────────────────────────────┤
│ ○ input                             │
│                           True  ──○ │
│                          False  ──○ │
└─────────────────────────────────────┘
```

**Logic options:**
- `all` (AND): All rules must pass → True
- `any` (OR): Any rule passes → True

---

## Switch Mode

Each rule becomes an independent output. First matching rule wins.

```
┌─────────────────────────────────────┐
│ ⑂ Condition                         │
├─────────────────────────────────────┤
│ 3 outputs + default                 │
├─────────────────────────────────────┤
│ ○ input                             │
│                        Healthy  ──○ │
│                        Wounded  ──○ │
│                        Critical ──○ │
│                         Default ──○ │
└─────────────────────────────────────┘
```

**Features:**
- Each rule has a `label` field for the output name
- Rules evaluated in order, first match wins
- `Default` output always present for unmatched cases
- No AND/OR logic toggle (each rule is independent)

---

## Operators by Variable Type

| Type | Operators |
|------|-----------|
| `text` | equals, not_equals, contains, starts_with, ends_with, is_empty |
| `number` | equals, not_equals, >, >=, <, <= |
| `boolean` | is_true, is_false, is_nil |
| `select` | equals, not_equals, is_nil |
| `multi_select` | contains, not_contains, is_empty |
| `date` | equals, not_equals, before, after |

---

## UI Components

### Properties Panel

```
┌─────────────────────────────────────┐
│ ⑂ Condition                       ✕ │
├─────────────────────────────────────┤
│ [✓] Switch mode                     │
│     Each condition creates an       │
│     output. First match wins.       │
│                                     │
│ Conditions (each = output)          │
│ ┌─────────────────────────────────┐ │
│ │ → [Healthy          ]         ✕ │ │
│ │ [Page ▼] [Variable ▼]           │ │
│ │ [Operator ▼] [Value]            │ │
│ └─────────────────────────────────┘ │
│ ...                                 │
│ [+ Add condition]                   │
│                                     │
│ Outputs:                            │
│ • Healthy                           │
│ • Wounded                           │
│ • Default (no match)                │
└─────────────────────────────────────┘
```

### Canvas Node

- Shows condition summary or output count
- Switch mode: displays rule labels as outputs
- Error indicators for incomplete rules

---

## Files Modified

| File | Purpose |
|------|---------|
| `lib/storyarn/flows/condition.ex` | Condition data structure, operators, rule management |
| `lib/storyarn_web/components/condition_builder.ex` | Visual condition builder component |
| `lib/storyarn_web/live/flow_live/components/node_type_helpers.ex` | Default node data |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex` | Condition node panel UI |
| `lib/storyarn_web/live/flow_live/show.ex` | Event handlers |
| `assets/js/hooks/flow_canvas/flow_node.js` | Dynamic output generation |
| `assets/js/hooks/flow_canvas/components/storyarn_node.js` | Canvas rendering |

---

## Future Enhancements

### Expression Mode (Deferred)
Raw text expression input for advanced users:
```
mc.jaime.health > 50 && mc.jaime.class == "warrior"
```

### Export Format
Ensure conditions export in evaluable format for game engines.
