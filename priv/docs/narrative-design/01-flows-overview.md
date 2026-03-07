%{
  title: "Flows Overview",
  category_label: "Narrative Design",
  order: 1,
  description: "Visual dialogue trees and branching narrative logic."
}
---

Flows are the heart of Storyarn — **visual node graphs** where you build branching dialogue and interactive narratives.

Each flow is a canvas of connected nodes that define how a conversation or sequence plays out.

---

## The editor

The flow editor is a full-screen canvas. Create nodes from the toolbar, connect them by dragging between pins, and edit content in the side panel.

Pan by dragging the background. Zoom with the scroll wheel.

---

## Node types

- **Entry** / **Exit** — where the flow starts and ends
- **Dialogue** (`D`) — character speech with optional player responses
- **Condition** (`C`) — branch based on variable values
- **Instruction** (`I`) — modify variable values
- **Hub** (`H`) — merge point where multiple paths converge
- **Jump** (`J`) — jump to a hub within the same flow
- **Slug Line** (`S`) — scene heading or location marker
- **Subflow** — embed another flow inside this one

---

## A typical structure

```
Entry
  → Slug Line ("INT. TAVERN - NIGHT")
    → Dialogue (NPC greeting)
      → Condition (has quest item?)
        → True: Dialogue (quest complete) → Instruction (give reward) → Exit
        → False: Dialogue (come back later) → Exit
```

Flows can be as simple as a linear conversation or as complex as an entire quest tree with dozens of branches.
