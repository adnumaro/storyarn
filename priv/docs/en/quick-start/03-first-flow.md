%{
  title: "Your First Flow",
  category_label: "Quick Start",
  order: 3,
  description: "Build a branching dialogue that reacts to character stats."
}
---

Now let's use the character sheet from the previous guide to build a dialogue where an NPC reacts to Jaime's health.

---

## Create the flow

Click **Flows** in the toolbar, then **+ New Flow**. Name it "Tavern Encounter".

The editor opens with an **Entry** node already placed on the canvas.

---

## Add dialogue

Click the **Dialogue** button in the toolbar (or press `D`) and place a node on the canvas. Connect Entry's output to the Dialogue's input.

Select the node and write the NPC's line:

> *"You look like you've been through a lot, traveler."*

---

## Add a condition

Add a **Condition** node (press `C`) and connect it after the dialogue.

In the side panel, open the **Condition Builder**:

1. Variable: `mc.jaime.health`
2. Operator: **Greater than**
3. Value: `50`

The node now has two outputs: **True** and **False**.

---

## Branch the conversation

Add two more Dialogue nodes:

- Connect **True** → *"Ah, you seem in good shape! What can I get you?"*
- Connect **False** → *"You're barely standing! Sit down, I'll bring a healing potion."*

Add an **Exit** node after each.

---

## Test with the debugger

Click the **Debug** button to open the debug panel. Click **Step** to advance through nodes one at a time.

The variable panel shows `mc.jaime.health = 100`. Since 100 > 50, the flow takes the True path.

Try changing health to `30` in the sheet and running again — now it takes the False path.

---

## What you've learned

Flows read variables from sheets in real time. Conditions branch on those values. The debugger lets you verify everything before integrating with your engine.
