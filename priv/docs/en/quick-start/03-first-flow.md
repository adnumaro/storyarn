%{
  title: "Your First Flow",
  category_label: "Quick Start",
  order: 3,
  description: "Build a branching dialogue that reacts to character stats."
}
---

Flows are where your narrative comes to life. In this guide you will build a short dialogue that branches based on the character sheet from the previous guide.

## Create the flow

Select **Flows** in the sidebar and click **New Flow**. Rename it to "Tavern Encounter".

The canvas opens with an {accent}Entry{/accent} node already placed -- this is where execution begins.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A new flow canvas with the Entry node and the "Add Node" dropdown visible in the top-right toolbar
</div>

## Add a dialogue node

Click the **Add Node** button in the top-right toolbar and select **Dialogue**. A new node appears on the canvas.

Connect the Entry node's output to the Dialogue node's input by dragging from one port to the other.

Select the Dialogue node and type the NPC's line directly on the node (double-click or press `E` to start inline editing):

> *"You look like you've been through a lot, traveler."*

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The Entry node connected to a Dialogue node with the NPC's line visible in the node body
</div>

## Add a condition

Add a **Condition** node from the toolbar and connect it after the Dialogue node.

Select the Condition node and click the settings icon in its floating toolbar (or press `E`) to open the {accent}Condition Builder{/accent} panel:

1. Select the variable `mc.jaime.health`
2. Set the operator to **Greater than**
3. Enter the value `50`

The Condition node now has two outputs: **True** and **False**.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The Condition Builder panel open on the right, with the variable mc.jaime.health selected, operator "Greater than", and value 50
</div>

## Branch the conversation

Add two more Dialogue nodes and connect them to the Condition outputs:

- **True** output -- *"Ah, you seem in good shape! What can I get you?"*
- **False** output -- *"You're barely standing! Sit down, I'll bring a healing potion."*

Add an {accent}Exit{/accent} node after each dialogue to end the flow.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The complete flow: Entry > Dialogue > Condition > two branching Dialogues > two Exit nodes
</div>

## Test with the debugger

Click the **Debug** button in the top-right toolbar (or press `Ctrl+Shift+D`) to open the debug panel at the bottom of the canvas.

The debug panel has three tabs:

- **Console** -- shows the execution output as it happens
- **Variables** -- displays all project variables and their current values
- **History** -- a step-by-step log of visited nodes

Click **Step** (or press `F10`) to advance through nodes one at a time. The variable panel shows `mc.jaime.health = 100`. Since 100 > 50, the flow takes the True path.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The debug panel open at the bottom showing the Console tab with execution output, and the highlighted True path on the canvas
</div>

Try changing the Health value to `30` on the character sheet and running the debugger again -- the flow will take the False path instead.

## Available node types

The flow editor supports these node types, all available from the **Add Node** dropdown:

| Node | Purpose |
|---|---|
| **Entry** | Starting point of the flow |
| **Exit** | Ends the flow (terminal, continue to another flow, or return to caller) |
| **Dialogue** | Character speech with optional responses, speaker, audio, and stage directions |
| **Condition** | Branches based on variable conditions (boolean or switch mode) |
| **Instruction** | Modifies variable values (assignments) |
| **Hub** | Named merge point that Jump nodes can target |
| **Jump** | Jumps execution to a Hub node |
| **Slug Line** | Screenplay-style scene heading (INT/EXT, location, time of day) |
| **Subflow** | Embeds another flow as a reusable sub-routine |
