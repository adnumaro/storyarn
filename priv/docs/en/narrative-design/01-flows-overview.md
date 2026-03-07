%{
  title: "Flows Overview",
  category_label: "Narrative Design",
  order: 1,
  description: "Visual dialogue trees and branching narrative logic."
}
---

Flows are the heart of Storyarn -- **visual node graphs** where you build branching dialogue, game logic, and interactive narratives. Each flow is a canvas of connected nodes that define how a conversation or sequence plays out, from a simple linear exchange to a sprawling quest tree with dozens of branches.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The flow editor canvas showing a branching dialogue tree with connected nodes
</div>

---

## The editor

The flow editor is a full-screen canvas. You create nodes from the floating toolbar, connect them by dragging between output and input pins, and edit content in the side panel that appears when you select a node.

- **Pan** by dragging the background
- **Zoom** with the scroll wheel
- **Select** a node by clicking it; double-click to open its primary editor (screenplay editor for dialogue, builder panel for conditions and instructions)
- **Multi-select** with click-drag or Shift+click
- **Duplicate** selected nodes with the context menu or keyboard shortcut
- **Undo/Redo** for node operations

Nodes are connected through **pins** -- small circles on the edges of each node. Drag from an output pin to an input pin to create a connection. Connections define the order in which nodes are executed during playback and debugging.

---

## Node types

Storyarn has **9 node types**, each serving a distinct role in the flow graph:

| Node | Icon | Purpose |
|------|------|---------|
| **Entry** | Play | Where the flow starts. Auto-created with the flow, cannot be deleted. Shows which other flows reference this one via subflow nodes. |
| **Exit** | Arrow right | Where the flow ends. Supports three modes: **Terminal** (ends entirely), **Continue to flow** (chains to another flow), and **Return to caller** (returns from a subflow). Has outcome tags and color coding. |
| **Dialogue** | Message square | Character speech with optional player responses. The most common node type -- see the [dedicated guide](/docs/narrative-design/dialogue-nodes). |
| **Condition** | Git branch | Branches the flow based on variable values. Visual builder with AND/OR logic -- no code required. Supports boolean mode (True/False outputs) and switch mode (multiple custom outputs). |
| **Instruction** | Zap | Modifies variable values when the flow passes through. Supports Set, Add, Subtract, Toggle, Clear, and boolean-specific operations. |
| **Hub** | Log in | A named merge point where multiple paths converge. Has a label, an ID, and a color. |
| **Jump** | Log out | Jumps to a Hub node within the same flow. Select a target hub from the toolbar dropdown; a crosshair button locates it on the canvas. |
| **Slug Line** | Clapperboard | Scene heading or location marker, borrowed from screenplay conventions. References a location sheet, with INT/EXT setting and time of day (day, night, morning, evening, continuous). |
| **Subflow** | Box | Embeds another flow inside this one. Dynamic output pins are generated from the referenced flow's Exit nodes, enabling branching based on how the subflow ends. Circular references are detected and prevented. |

---

## A typical structure

```
Entry
  -> Slug Line ("INT. TAVERN - NIGHT")
    -> Dialogue (NPC greeting)
      -> Condition (has quest item?)
        -> True: Dialogue (quest complete)
             -> Instruction (give reward, mark quest done)
               -> Exit (Terminal, outcome: "quest_complete")
        -> False: Dialogue (come back later)
             -> Exit (Terminal, outcome: "quest_pending")
```

Flows can be as simple as a linear conversation or as complex as an entire quest tree. Use **Hub** and **Jump** nodes to merge converging paths without duplicating dialogue. Use **Subflow** nodes to compose larger narratives from reusable flow fragments.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A flow with hub/jump nodes showing how multiple dialogue branches converge into a single path
</div>

---

## Subflows and nested execution

Subflow nodes let you embed one flow inside another. When the execution reaches a subflow node, it enters the referenced flow's Entry node and runs through it. When it hits an Exit node with **Return to caller** mode, execution returns to the parent flow and continues from the corresponding output pin.

Each Exit node in the referenced flow creates a separate output pin on the subflow node, so the parent flow can branch based on which exit the subflow took. The debugger and Story Player both support full cross-flow navigation with a call stack, so nested subflows work exactly as you would expect.

---

## {accent}Story Player{/accent}

Click **Play** in the toolbar to experience your flow as a player would. The {accent}Story Player{/accent} is a full-screen cinematic view that auto-advances through non-interactive nodes (conditions, instructions, hubs, jumps, slug lines) and stops only at dialogue nodes where you read lines or make choices.

- Scene backdrops from linked scenes dim behind the dialogue
- Navigate back through history with the back button
- **Keyboard controls**: 1-9 to select responses, Space/Enter to continue, Escape to exit
- **Restart** the flow at any time to replay from the beginning
- Subflows are followed automatically -- the player handles the full call stack

Toggle {accent}Analysis mode{/accent} to see hidden responses that failed their conditions, shown as greyed-out options with strikethrough text. This helps you verify that conditional responses are working as intended without editing the flow.

This is not a preview. It is the actual playthrough experience, with real variable evaluation and state changes.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The Story Player showing a dialogue with response choices and a scene backdrop
</div>

---

## {accent}Debug Mode{/accent}

Most narrative tools force you to playtest by running the whole game. Storyarn has a built-in {accent}debugger{/accent} -- step through your flow node by node, inspect every variable in real time, set breakpoints, and see exactly which path was taken and why.

- **Step** advances one node at a time
- **Step Back** rewinds to the previous state
- **Run** auto-advances at configurable speed (200ms-3000ms per step), stopping at breakpoints and player choices
- **Reset** restarts from the start node
- **Start from any node** -- pick any node in the flow as the starting point
- **Breakpoints** -- click the dot next to any node in the Path tab to set a breakpoint; auto-play stops there
- **4 information tabs**: Console (log with timestamps and rule evaluation details), Variables (live values with filtering, inline editing, and change tracking), History (every variable change with source attribution), and Path (visual execution trace with breakpoint controls)
- **Edit variables mid-session** -- click any variable value in the Variables tab to change it, then continue execution to test alternate paths

Change a variable value, reset, and re-run to test alternate paths. No game engine needed, no export cycle -- verify your logic right where you write it.

For a detailed walkthrough, see the [Debug Mode guide](/docs/narrative-design/debug-mode).
