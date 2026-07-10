%{
title: "Flows Overview",
category_label: "Narrative Design",
order: 1,
description: "Visual dialogue trees and branching narrative logic."
}

---

Flows are the heart of Storyarn -- **visual node graphs** where you build branching dialogue, game logic, and interactive narratives. Each flow is a canvas of connected nodes that define how a conversation or sequence plays out, from a simple linear exchange to a sprawling quest tree with dozens of branches.

<img src="/images/docs/flows-editor-current.png" alt="Flow editor canvas with connected dialogue, condition, instruction, hub, subflow, and exit nodes" loading="lazy">

---

## The editor

The flow editor is a full-screen canvas. You create nodes from the floating toolbar, connect them by dragging between output and input pins, and edit content in the side panel that appears when you select a node.

- **Pan** by dragging the background
- **Zoom** with the scroll wheel
- **Select** a node by clicking it; double-click to open its primary editor (focused dialogue editor for dialogue, builder panel for conditions and instructions)
- **Multi-select** with click-drag or Shift+click
- **Duplicate** selected nodes with the context menu or keyboard shortcut
- **Undo/Redo** for node operations

Nodes are connected through **pins** -- small circles on the edges of each node. Drag from an output pin to an input pin to create a connection. Connections define the order in which nodes are executed during playback and debugging.

---

## Node types

Storyarn has **10 node types**, each serving a distinct role in the flow graph:

| Node            | Icon           | Purpose                                                                                                                                                                                                |
| --------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Entry**       | Play           | Where the flow starts. Auto-created with the flow, cannot be deleted. See [Entry & Exit Nodes](/docs/narrative-design/node-types/entry-exit).                                                          |
| **Exit**        | Arrow right    | Where the flow ends. Supports terminal, continue-to-flow, and return-to-caller modes. See [Entry & Exit Nodes](/docs/narrative-design/node-types/entry-exit).                                          |
| **Dialogue**    | Message square | Character speech with optional player responses. The most common node type -- see the [dedicated guide](/docs/narrative-design/node-types/dialogue).                                                   |
| **Condition**   | Git branch     | Branches the flow based on variable values. See [Condition Nodes](/docs/narrative-design/node-types/condition) and the [Condition Editor](/docs/narrative-design/condition-editor).                    |
| **Instruction** | Zap            | Modifies variable values when the flow passes through. See [Instruction Nodes](/docs/narrative-design/node-types/instruction) and the [Instruction Editor](/docs/narrative-design/instruction-editor). |
| **Hub**         | Log in         | A named merge point where multiple paths converge. See [Hub & Jump Nodes](/docs/narrative-design/node-types/hub-jump).                                                                                 |
| **Jump**        | Log out        | Jumps to a Hub node within the same flow. See [Hub & Jump Nodes](/docs/narrative-design/node-types/hub-jump).                                                                                          |
| **Subflow**     | Box            | Embeds another flow inside this one. See [Subflow Nodes](/docs/narrative-design/node-types/subflow).                                                                                                   |
| **Sequence**    | Panels top     | Groups related nodes inside a visual container. See [Sequence Nodes](/docs/narrative-design/node-types/sequence).                                                                                      |
| **Annotation**  | Sticky note    | Purely visual note for design intent, TODOs, or context on the canvas. See [Annotation Nodes](/docs/narrative-design/node-types/annotation).                                                           |

---

## A typical structure

```
Sequence ("Tavern encounter")
  Entry
    -> Dialogue (NPC greeting)
      -> Condition (has quest item?)
        -> True: Dialogue (quest complete)
             -> Instruction (give reward, mark quest done)
               -> Exit (Terminal, outcome: "quest_complete")
        -> False: Dialogue (come back later)
             -> Exit (Terminal, outcome: "quest_pending")
```

Flows can be as simple as a linear conversation or as complex as an entire quest tree. Use **Hub** and **Jump** nodes to merge converging paths without duplicating dialogue. Use **Subflow** nodes to compose larger narratives from reusable flow fragments.

<img src="/images/docs/flows-editor-current.png" alt="A flow with hub and jump nodes showing how multiple dialogue branches converge into a single path" loading="lazy">

---

## Subflows and nested execution

Subflow nodes let you embed one flow inside another. When the execution reaches a subflow node, it enters the referenced flow's Entry node and runs through it. When it hits an Exit node with **Return to caller** mode, execution returns to the parent flow and continues from the corresponding output pin.

Each Exit node in the referenced flow creates a separate output pin on the subflow node, so the parent flow can branch based on which exit the subflow took. The debugger and Story Player both support full cross-flow navigation with a call stack, so nested subflows work exactly as you would expect.

---

## {accent}Story Player{/accent}

Click **Play** in the toolbar to experience your flow as a player would. The {accent}Story Player{/accent} is a full-screen cinematic view that auto-advances through non-interactive nodes (entry, hubs, conditions, instructions, jumps, and subflows) and stops only at dialogue nodes where you read lines or make choices.

- Scene backdrops from linked scenes dim behind the dialogue
- Navigate back through history with the back button
- **Keyboard controls**: 1-9 to select responses, Space/Enter to continue, Escape to exit
- **Restart** the flow at any time to replay from the beginning
- Subflows are followed automatically -- the player handles the full call stack

Toggle {accent}Analysis mode{/accent} to see hidden responses that failed their conditions, shown as greyed-out options with strikethrough text. This helps you verify that conditional responses are working as intended without editing the flow.

This is not a preview. It is the actual playthrough experience, with real variable evaluation and state changes.

<img src="/images/docs/flows-player-current.png" alt="The Story Player showing a dialogue with response choices and a scene backdrop" loading="lazy">

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
