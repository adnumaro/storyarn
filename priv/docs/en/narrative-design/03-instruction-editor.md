%{
title: "Instruction Editor",
category_label: "Narrative Design",
order: 3,
description: "Use Builder view and Code view to write variable assignments for flows, responses, zones, and pins."
}

---

The Instruction Editor defines assignments that write to variables. Storyarn uses the same editor anywhere runtime logic needs to change state:

| Where | When instructions run |
| ----- | --------------------- |
| **Instruction nodes** | When the flow reaches the node. |
| **Dialogue responses** | When the player chooses that response. |
| **Scene zones** | When the zone action is triggered during exploration. |
| **Scene pins** | When the pin action is triggered during exploration. |

Instructions can write literal values or copy values from another variable. Use the [Condition Editor](/docs/narrative-design/condition-editor) when you only need to check state.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Instruction Editor showing Builder and Code tabs with multiple assignments
</div>

## Editing modes

Every instruction set has two editing modes:

| Mode | Best for | What you edit |
| ---- | -------- | ------------- |
| **Builder view** | Most users, readable state changes, fewer syntax mistakes | Sentence-style assignment rows. |
| **Code view** | Technical designers, fast edits, compact multi-line updates | One assignment per line, such as `mc.jaime.gold += 100`. |

Switching to Code view serializes the current assignments into text. Editing Code view parses the text back into the structured assignment data used by Storyarn.

## Builder view

Builder view reads like natural language:

```text
Set mc.jaime · health to 75
Add 100 to mc.jaime · gold
Toggle quest.door · unlocked
```

Each assignment has:

1. An operation.
2. A target variable.
3. A value, unless the operation does not need one.

A single editor can contain multiple assignments. They execute in order.

## Operations

| Operation | Code view syntax | Variable types |
| --------- | ---------------- | -------------- |
| **Set** | `mc.jaime.health = 75` | All writable types |
| **Add** | `mc.jaime.gold += 100` | Number |
| **Subtract** | `mc.jaime.health -= 25` | Number |
| **Set true** | `quest.door.unlocked = true` | Boolean |
| **Set false** | `quest.door.unlocked = false` | Boolean |
| **Toggle** | `toggle quest.door.unlocked` | Boolean |
| **Clear** | `clear mc.jaime.notes` | Text and rich text |

The available operations depend on the selected variable type. For example, a number can be set, added to, or subtracted from, while a boolean can be set true, set false, or toggled.

## Literal values and variable references

Most assignments use literal values:

```text
mc.jaime.health = 75
```

You can also switch the value input into variable-reference mode:

```text
mc.jaime.health = mc.jaime.max_health
```

That copies the current value of `max_health` into `health` when the instruction runs.

## Code view

Code view uses one assignment per line:

```text
quest.tavern.accepted = true
mc.jaime.gold += 100
mc.jaime.health = mc.jaime.max_health
clear mc.jaime.notes
```

Code view supports autocomplete, linting, and formatting. If a line cannot be parsed into a supported assignment, fix it before relying on it in player, debug, or exploration mode.

## Choosing where to put instructions

Use a dedicated Instruction node when the state change is important enough to see in the flow structure, when several values change together, or when the update should happen regardless of which dialogue response the player chose.

Use response, zone, or pin instructions when the state change belongs to that specific interaction.
