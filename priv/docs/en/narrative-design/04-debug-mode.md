%{
  title: "Debug Mode",
  category_label: "Narrative Design",
  order: 4,
  description: "Test and verify your flows with the built-in debugger."
}
---

The flow editor includes a built-in **debugger** that lets you simulate how a flow executes — step by step, with full visibility into variable values and decision paths.

## Starting a debug session

1. Open a flow in the editor
2. Click the **Debug** button in the toolbar
3. The debug panel appears at the bottom of the screen

The debugger starts at the flow's **Entry** node.

## Controls

| Action | What it does |
|--------|-------------|
| **Step** | Advance to the next node |
| **Run** | Auto-advance until a dialogue node with responses (player choice) |
| **Reset** | Restart from the Entry node |

## What you can see

### Variable panel

Shows all variables referenced in the flow and their current values. Values update in real time as instruction nodes are executed.

### Execution history

A log of every node visited, in order. Useful for understanding which path was taken and why.

### Active node highlighting

The currently active node is highlighted on the canvas, making it easy to follow the execution visually.

## Testing different paths

To test alternate paths:

1. Change variable values in the sheets
2. Reset and re-run the debugger
3. The flow will take different branches based on the new values

This is the fastest way to verify that all your conditions and instructions work correctly before integrating with a game engine.
