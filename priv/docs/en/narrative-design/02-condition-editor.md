%{
title: "Condition Editor",
category_label: "Narrative Design",
order: 2,
description: "Use Builder view and Code view to define reusable variable checks for flows, responses, zones, and pins."
}

---

The Condition Editor defines checks that read variables and return true or false. Storyarn uses the same editor in several places:

| Where                  | What the condition controls                                                           |
| ---------------------- | ------------------------------------------------------------------------------------- |
| **Condition nodes**    | Which flow branch runs next.                                                          |
| **Dialogue responses** | Whether a player response is available.                                               |
| **Scene zones**        | Whether an area is visible or interactive during exploration.                         |
| **Scene pins**         | Whether a marker, character, or hotspot is visible or interactive during exploration. |

Conditions only read variables. They do not change state. Use the [Instruction Editor](/docs/narrative-design/instruction-editor) when you need to write values.

<img src="/images/docs/flows-condition-builder.png" alt="Flow editor canvas with a condition node and its branching connections" loading="lazy">

## Editing modes

Every condition has two editing modes:

| Mode             | Best for                                                    | What you edit                                                                    |
| ---------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------- |
| **Builder view** | Most users, readable production logic, collaborative review | Sentence-style blocks made from variables, operators, values, and logic groups.  |
| **Code view**    | Technical designers, fast edits, compact expressions        | A text expression such as `mc.jaime.health > 50 && quest.door.unlocked == true`. |

The two modes describe the same condition. Switching to Code view serializes the current builder state into text. Editing Code view parses the text back into the structured condition data used by Storyarn.

## Builder view

Builder view creates conditions from blocks and rules.

| Level     | Purpose                                                                                                |
| --------- | ------------------------------------------------------------------------------------------------------ |
| **Rule**  | One variable/operator/value comparison, such as `mc.jaime.health > 50`.                                |
| **Block** | A set of rules combined with **All (AND)** or **Any (OR)**.                                            |
| **Group** | A nested set of selected blocks with its own **All** or **Any** logic. Groups behave like parentheses. |

A simple condition reads like a sentence:

```text
mc.jaime · health is greater than 50
```

Use **Group selected** when a subset of blocks needs to be evaluated together:

```text
(mc.jaime.has_key && door.lock_level < 3) || mc.jaime.is_admin
```

In builder terms, group the key and lock-level checks with **All**, then combine that group with the admin check using **Any**.

## Operators by variable type

| Variable type        | Common operators                                        |
| -------------------- | ------------------------------------------------------- |
| **Number**           | equals, not equals, greater than, less than, is not set |
| **Text / Rich text** | equals, contains, starts with, ends with, is empty      |
| **Boolean**          | is true, is false, is not set                           |
| **Select**           | equals, not equals, is not set                          |
| **Multi-select**     | contains, does not contain, is empty                    |
| **Date**             | equals, before, after, is not set                       |

The available operators depend on the selected variable type, so the builder prevents invalid comparisons where possible.

## Code view

Code view is the expression editor. It is useful when you already know the variable paths or when an expression is faster to type than to assemble visually.

```text
mc.jaime.health > 50 && (quest.door.unlocked == true || mc.jaime.has_key == true)
```

Code view supports autocomplete, linting, and formatting. Use formatting after editing a longer expression so parentheses and logical groups remain readable.

If an expression cannot be parsed into supported condition data, fix the expression before relying on it in player, debug, or exploration mode.

## Condition nodes and switch mode

The editor is shared, but some host features are specific to the place where the condition is used.

Condition nodes can use **Boolean** output mode or **Switch** output mode. In switch mode, each condition block becomes an output branch and the first matching block wins. Dialogue responses, zones, and pins do not use switch outputs; they use the condition as a gate.
