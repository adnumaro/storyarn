%{
title: "Hub & Jump Nodes",
category_label: "Narrative Design",
section_label: "Node Types",
section_order: 1,
order: 5,
description: "Merge branches and jump to named points without duplicating dialogue."
}

---

Hub and Jump nodes work together. A Hub is a named destination in the flow. A Jump sends execution to that destination.

Use them when several branches need to converge into the same continuation without drawing long crossing connections or duplicating the same nodes.

<img src="/images/docs/flows-editor-current.png" alt="Flow canvas with several branches using Jump nodes to converge into one Hub" loading="lazy">

## Hub nodes

A Hub node marks a named point in the flow. Give it a clear label and stable hub ID, such as `after_intro`, `quest_acceptance`, or `combat_setup`.

The Hub toolbar shows references from Jump nodes, so you can see which parts of the flow target it.

## Jump nodes

A Jump node selects a target Hub. When execution reaches the Jump, the flow continues from the selected Hub.

Use the locate action in the toolbar when you need to jump the canvas view to the target Hub.

## Good uses

- Several dialogue responses rejoin into the same follow-up.
- A condition has multiple failure branches that all return to a shared retry point.
- A long flow has named checkpoints that keep connections readable.
- You want to avoid duplicating identical dialogue or instructions.

## Avoid overusing them

Hub and Jump nodes make large graphs cleaner, but too many jumps can make flow execution harder to follow. Prefer direct connections while the graph is small. Add hubs when connection lines become noisy or duplicated content starts appearing.
