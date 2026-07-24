%{
title: "Structural Analysis",
category_label: "Narrative Design",
order: 5,
description: "Deterministic flow structure findings with evidence, limitations, and reversible dismissal."
}

---

Structural analysis inspects the **shape of a flow's graph** and reports problems it can prove: missing entries, unreachable branches, dead ends, broken pins, and stale references. Every finding is deterministic — the same flow always produces the same findings, computed from your graph alone.

Analysis is a **free capability**: it makes no AI calls, consumes no AI allowance, and works even when every AI provider is disabled.

---

## Running an analysis

Open the panel from the **health indicator** in the flow editor toolbar, or run **Analyze current flow** from the command palette. Both compute a fresh snapshot of findings for the current flow.

The panel splits findings into two categories:

- **Structure** — missing or multiple Entry nodes, nodes unreachable from Entry, isolated nodes, dead ends, unconnected required output pins, connections on removed pins, and hubs nothing reaches.
- **References** — jump, subflow, and exit nodes whose target no longer exists or was never set.

Editorial warnings (empty dialogue text, incomplete conditions, missing speakers) stay in the toolbar health popover — they are about content completeness, not structure.

## Reading a finding

Selecting a finding shows:

- **What was detected** — the deterministic fact, such as which node has no outgoing connection.
- **Limitations** — what the rule does _not_ prove. Reachability is topological: conditions are never evaluated, so a node the analysis considers reachable may still be unreachable in actual play.
- **Evidence** — the nodes and connections behind the conclusion. **Go to** centers the canvas on a node or highlights the exact connection.

## When the flow changes

The snapshot is explicit. If the flow's structure changes while the panel is open, the panel marks the analysis **outdated** and offers a rerun — it never silently mixes old results with new evidence.

A finding disappears on rerun when the underlying problem is gone. There is nothing to "mark as fixed": resolution is derived from the graph.

## Dismissing a finding

Sometimes the detection is correct but the structure is intentional, or the rule doesn't apply to how your project works. **Dismiss finding** records that decision for the whole project, with a required reason:

| Reason                   | When to use it                                                |
| ------------------------ | ------------------------------------------------------------- |
| Intentional design       | The structure exists and is deliberate                        |
| Rule not applicable here | The flow type or project conventions make the rule irrelevant |
| Missing context          | Something outside Storyarn invalidates the conclusion         |
| Incorrect detection      | The evidence or conclusion is wrong for this data             |
| Duplicate finding        | Another finding already covers the same problem               |
| Other                    | Anything else — requires a note                               |

Dismissals are **reversible** (restore them from the Dismissed tab), shared with the whole project, and recorded with who dismissed and why. A dismissal applies to the exact occurrence it was made on: if the rule is updated or the surrounding structure changes, the finding reactivates on the next analysis.

Dismissing and restoring require edit permission on the flow. Viewers can open the panel, inspect findings, and navigate evidence, but cannot change dispositions.

## Scope

Structural analysis runs in the normal flow editor, one flow at a time. Compact and comparison views link back to the editor instead of embedding the panel. Whole-project semantic analysis, condition satisfiability, and narrative-quality scoring are out of scope by design.
