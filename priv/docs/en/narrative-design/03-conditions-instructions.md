%{
  title: "Conditions & Instructions",
  category_label: "Narrative Design",
  order: 3,
  description: "Branch your narrative with conditions and modify game state with instructions."
}
---

Conditions read your variables to make decisions. Instructions write to your variables to change game state. Together, they are how flows interact with your world data -- the bridge between narrative and game logic.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A condition node connected to two dialogue branches (True and False outputs)
</div>

---

## Condition nodes

A condition node evaluates rules against your project's variables and routes the flow to different outputs based on the result.

The {accent}**Condition Builder**{/accent} is a fully visual interface -- no code needed. Double-click a condition node (or click the settings button in its toolbar) to open the builder panel. Each rule follows three steps:

1. **Pick a variable** -- select a sheet and variable (e.g., `mc.jaime.health`)
2. **Choose an operator** -- the available operators depend on the variable's type
3. **Set a value** to compare against

---

## Operators by variable type

Different variable types support different comparison operators:

| Variable type | Available operators |
|--------------|-------------------|
| **Number** | equals, not equals, greater than, greater than or equal, less than, less than or equal, is not set |
| **Text / Rich text** | equals, not equals, contains, starts with, ends with, is empty, is not set |
| **Boolean** | is true, is false, is not set |
| **Select** | equals, not equals, is not set |
| **Multi-select** | contains, does not contain, is empty, is not set |
| **Date** | equals, before, after, is not set |

---

## Logic groups

Combine multiple rules with **All (AND)** or **Any (OR)** logic:

> *"Match **all** of the rules: Jaime has more than 50 health AND has the key"*
> Both must be true for the condition to pass.

> *"Match **any** of the rules: Player is a Mage OR has the spell scroll"*
> Either one is enough.

You can also group rules into **blocks** for more complex nested logic. Select multiple rules and click **Group selected** to combine them into a sub-group with its own AND/OR toggle.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The Condition Builder panel showing grouped rules with AND/OR logic toggles
</div>

---

## Output modes

Condition nodes support two output modes, toggled from the toolbar:

### Boolean mode (default)

The condition evaluates to **True** or **False**. The node has two output pins, and the flow follows whichever one matches. This is the most common setup for simple yes/no branching.

### Switch mode

Each rule (or block of rules) creates its own labeled output pin. The flow follows the **first matching** output. This is useful for multi-way branching -- like checking a character's class with separate outputs for Warrior, Mage, and Rogue.

In switch mode, each condition block gets a **label** field that becomes the output pin's name on the canvas. The toolbar shows a split icon when switch mode is active.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A condition node in switch mode with three labeled output pins (Warrior, Mage, Rogue)
</div>

---

## Instruction nodes

Instruction nodes **modify variables** when the flow passes through them. Double-click a node (or click the settings button) to open the {accent}Instruction Builder{/accent}.

Each instruction is a **natural language sentence** that reads like a command:

| Operation | Sentence | Effect | Variable types |
|-----------|----------|--------|---------------|
| **Set** | Set `mc.jaime` . `health` to `75` | Assigns a value | All types |
| **Add** | Add `100` to `mc.jaime` . `gold` | Adds to current value | Number |
| **Subtract** | Subtract `25` from `mc.jaime` . `health` | Subtracts from current value | Number |
| **Set true** | Set `quest.door` . `unlocked` to true | Sets boolean to true | Boolean |
| **Set false** | Set `quest.door` . `unlocked` to false | Sets boolean to false | Boolean |
| **Toggle** | Toggle `quest.door` . `unlocked` | Flips boolean value | Boolean |
| **Clear** | Clear `mc.jaime` . `notes` | Removes the value | Text, Rich text |

A single instruction node can contain **multiple assignments** that execute in order. Click **Add assignment** to create a new row.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The Instruction Builder with three assignments: Set health, Add gold, Toggle quest flag
</div>

---

## Variable references in instructions

By default, instruction values are **literal** -- you type a number or string directly. But you can switch any value slot to a **variable reference**, which reads the current value of another variable at execution time.

> *Example: Set `mc.jaime` . `health` to `mc.jaime` . `max_health`*
> This copies the value of max_health into health.

Click the toggle icon next to the value input to switch between literal value and variable reference modes.

---

## When to use inline vs. dedicated nodes

Dialogue responses support inline conditions and instructions for simple cases (see the [Dialogue Nodes guide](/docs/narrative-design/dialogue-nodes)). Use dedicated Condition and Instruction nodes when:

- The same condition is checked by **multiple paths** in the flow
- The logic involves **multiple rules** with complex AND/OR grouping
- Several variables need to **change together** as a single logical step
- You want the logic to be **visible on the canvas** for easier debugging and collaboration
- You need **switch mode** for multi-way branching

As a rule of thumb: if the logic belongs to a specific response choice, put it inline. If it belongs to the flow structure, use a node.
