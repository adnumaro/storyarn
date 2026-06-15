%{
title: "Entry & Exit Nodes",
category_label: "Narrative Design",
section_label: "Node Types",
section_order: 1,
order: 1,
description: "Where a flow starts, how it ends, and how outcomes connect larger narrative structures."
}

---

Entry and Exit nodes define the boundaries of a flow. They are simple on the canvas, but they matter because they decide how a flow starts, when it finishes, and how other flows can call into or return from it.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Flow canvas showing the Entry node connected to a short branch and multiple Exit nodes with outcome labels
</div>

## Entry nodes

Every flow has one Entry node. It is created with the flow and cannot be deleted. Execution begins here when you run the flow in the Story Player, debug the flow, or enter it from a Subflow node.

Entry nodes are mostly structural. Use them as the first connection point in the flow, then branch into the first dialogue, condition, sequence, or setup instruction.

## Exit nodes

Exit nodes mark where a path finishes. A flow can have one exit or many exits, depending on how much outcome information you need to expose to callers.

Common examples:

| Use case                                    | Exit setup                                              |
| ------------------------------------------- | ------------------------------------------------------- |
| A simple conversation ends                  | One terminal Exit node                                  |
| A quest branch succeeds or fails            | Separate exits like `accepted`, `declined`, `completed` |
| A reusable subflow returns to a parent flow | Exit nodes configured to return to caller               |
| A flow hands off to another flow            | Exit node configured to continue to another flow        |

## Exit modes

Exit nodes support three modes:

| Mode                 | Behavior                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| **Terminal**         | Ends the current run. Use it when the flow is complete.                                           |
| **Continue to flow** | Jumps into another flow after this path ends. Use it for explicit flow chaining.                  |
| **Return to caller** | Returns to the parent flow that entered through a Subflow node. Use it for reusable nested flows. |

## Outcome tags

Outcome tags describe what happened on that path. They make exits easier to read in the canvas and give Subflow callers meaningful output pins.

For example, a reusable negotiation flow might expose exits named:

```text
accepted
refused
needs_payment
failed_check
```

When another flow uses it as a Subflow, those outcomes become the branches the parent flow can connect to.

## Practical pattern

For small flows, one terminal Exit node is enough. For reusable flows, define exits around the decisions the caller cares about. Avoid creating exits for internal implementation details that no parent flow needs to know.
