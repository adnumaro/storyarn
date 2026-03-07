%{
  title: "Debug Mode",
  category_label: "Narrative Design",
  order: 4,
  description: "Test and verify your flows with the built-in debugger."
}
---

The flow editor includes a built-in {accent}debugger{/accent} that lets you simulate how a flow executes -- step by step, with full visibility into variable values, decision paths, and execution history. This is something no other narrative design tool offers: you can verify your entire branching logic without leaving the editor, without exporting, and without a game engine.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The flow editor with the debug panel open at the bottom, showing the console tab with execution logs
</div>

---

## Starting a debug session

1. Open a flow in the editor
2. Click the **Debug** button in the toolbar
3. The debug panel appears docked at the bottom of the canvas

The debugger initializes at the flow's **Entry** node, loading all project variables with their current values from the sheets.

---

## Controls

The control bar sits at the top of the debug panel with the following actions:

| Button | Action | What it does |
|--------|--------|-------------|
| Play / Pause | **Auto-play** | Auto-advances the flow at the configured speed, pausing at dialogue choices and breakpoints |
| Step | **Step** | Advances exactly one node forward |
| Step Back | **Step Back** | Rewinds to the previous state (undo the last step) |
| Reset | **Reset** | Restarts the session from the start node, resetting all variables to their initial values |
| Stop | **Stop** | Ends the debug session and closes the panel |

When the debugger reaches a **dialogue node with responses**, it stops and presents the available choices as buttons in the console. Responses whose conditions are not met appear greyed out and disabled. Click a valid response to continue execution along that path.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The debug controls bar showing Step, Step Back, Reset, Stop buttons with status badge and step counter
</div>

---

## Start from any node

You are not limited to starting from the Entry node. The **Start** dropdown in the controls bar lists every node in the flow. Select a different node to start debugging from that point -- the session resets and begins at the selected node.

This is invaluable for testing a specific branch deep in a complex flow without stepping through dozens of nodes to get there.

---

## Speed control

The **speed slider** controls how fast auto-play advances, ranging from **200ms** (5 steps per second, fast) to **3000ms** (one step every 3 seconds, slow). The current speed is displayed next to the slider.

Use a fast speed to quickly scan through a long flow, or a slow speed to watch each step carefully. Auto-play pauses automatically at breakpoints and at dialogue nodes that require a response.

---

## Active node highlighting

The currently active node is **highlighted on the canvas** in real time. The entire execution path is also visually traced, so you can see the full route taken through the flow. The active connection between the last two nodes is highlighted as well.

The canvas auto-centers on the active node as you step through the flow, so you never lose track of where you are.

---

## The four tabs

The debug panel has four information tabs, each giving you a different view of the execution state.

### Console

A timestamped log of everything that happens during execution. Each entry shows:

- **Timestamp** in seconds (e.g., `0.012s`)
- **Level icon** -- info (blue), warning (yellow), or error (red)
- **Node label** -- which node produced the entry
- **Message** -- what happened (condition evaluated, instruction executed, error encountered)

For condition evaluations, the console shows **per-rule details**: which variable was checked, what the expected value was, what the actual value was, and whether the rule passed or failed. This is the fastest way to understand why a condition took a specific branch.

When the debugger is waiting for a response, the available choices appear at the bottom of the console tab as clickable buttons.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The Console tab showing timestamped entries with condition rule details (variable, expected, actual, pass/fail)
</div>

### Variables

A live table of **every variable** in the project, with five columns:

| Column | Shows |
|--------|-------|
| **Variable** | The full reference (sheet shortcut + variable name) |
| **Type** | The variable's block type (number, boolean, text, select, etc.) |
| **Initial** | The value when the debug session started |
| **Previous** | The value before the most recent change |
| **Current** | The live value right now |

Changed variables are highlighted -- values modified by instructions appear in **yellow**, and values you manually override appear in **blue**. A diamond indicator marks variables whose current value differs from their initial value.

The Variables tab includes two filtering tools:

- **Search filter** -- type to filter variables by name
- **Changed only toggle** -- show only variables that have been modified during the session

Column widths are **resizable** -- drag the column borders to adjust them.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The Variables tab showing a table with Initial, Previous, and Current columns, with changed values highlighted
</div>

### History

A chronological log of **every variable change** that occurred during the session. Each entry shows:

- **Timestamp** -- when the change happened
- **Node** -- which node caused the change (or "(user override)" if you edited it manually)
- **Change** -- the variable reference, old value, arrow, and new value
- **Source** -- either "instr" (changed by an instruction node) or "user" (changed by manual edit)

This is useful for tracking down exactly when and where a variable was set to an unexpected value.

### Path

A visual trace of **every node visited**, in execution order. Each entry shows:

- **Step number** -- sequential count
- **Breakpoint dot** -- click to toggle a breakpoint on this node
- **Node type icon** -- the node type's icon
- **Node label** -- the node's text content (truncated)
- **Outcome** -- what the node produced (condition result, instruction effect, etc.)

The current node is highlighted in the path. When debugging across subflows, **flow separators** appear in the path showing "Entering sub-flow" and "Returned to parent" markers, with entries indented to show the call depth.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The Path tab showing the execution trace with step numbers, breakpoint dots, and a sub-flow separator
</div>

---

## {accent}Breakpoints{/accent}

Click the **dot** next to any node in the Path tab to set a {accent}breakpoint{/accent}. Active breakpoints appear as solid red circles; unset breakpoints are hollow circles that turn red on hover.

When auto-play is running and the execution reaches a node with a breakpoint, it **stops automatically** and auto-play is paused. This lets you run through large sections of a flow at speed and stop precisely where you need to inspect.

Breakpoints are also visually indicated on the canvas nodes themselves, so you can see at a glance which nodes will cause a pause.

---

## {accent}Editing variables mid-session{/accent}

Click any variable's **current value** in the Variables tab to edit it inline. The input type adapts to the variable:

- **Number** variables get a number input
- **Boolean** variables get a true/false dropdown
- **Text** and other types get a text input

Press Enter to confirm, or Escape to cancel. The change is logged in the History tab with a "user" source tag, and the variable's current value turns **blue** to indicate a manual override.

After changing a variable, you can **reset** and re-run the flow to see how it behaves with the new value, or simply continue stepping from the current position. This is the fastest way to test "what if" scenarios without modifying your actual sheet data.

---

## Cross-flow debugging

When the debugger steps into a **subflow node**, it automatically navigates to the referenced flow and continues execution inside it. A **breadcrumb bar** appears above the controls showing the call stack:

> *Parent Flow > Sub Flow > Current*

The debugger maintains the full state across flow boundaries -- variables, execution history, console log, and breakpoints all persist. When a subflow reaches an Exit node with "Return to caller" mode, the debugger navigates back to the parent flow and continues from the subflow node's output pin.

Reset always returns to the **root flow** -- the flow where the debug session originally started.

---

## Infinite loop protection

The debugger includes a **step limit** (shown in the warning banner) to protect against infinite loops. If the execution exceeds the limit, auto-play stops and a warning appears with the option to **Continue (+1000 steps)**. This extends the limit and lets you keep debugging if the loop is intentional or if the flow simply has many steps.

---

## Panel resizing

The debug panel can be **resized vertically** by dragging the handle at the top edge. Drag it up to see more information, or down to see more of the canvas. The panel maintains its height until you resize it again.

---

## Tips for effective debugging

- **Use breakpoints** to skip through known-good sections and stop at the logic you want to verify
- **Filter to changed variables** to quickly see what instructions modified
- **Edit variables** to test edge cases (zero health, empty inventory, maximum values)
- **Start from a specific node** to jump directly to the section you are working on
- **Check the Console** for condition rule details when a branch takes an unexpected path -- it shows exactly which rules passed and failed, with actual vs. expected values
- **Use Step Back** when you miss something -- you can rewind and re-examine without resetting the entire session
