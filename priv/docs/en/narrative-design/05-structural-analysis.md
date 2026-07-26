%{
title: "Flow Health",
category_label: "Narrative Design",
order: 5,
description: "Deterministic checks over a flow's graph and its node content, in the editor and across the project."
}

---

Flow health inspects two things at once: the **shape of a flow's graph** -- missing entries, unreachable branches, dead ends, broken pins, targets that no longer exist -- and the **content of each node** -- empty dialogue lines, half-finished conditions, missing speakers, stale variable references.

Both halves share a single catalog of checks, so the flow editor and the Flows dashboard can never word the same problem differently, and neither can hide a problem the other reports.

Every check is deterministic: the same flow always produces the same findings, computed from your data alone. Flow health is a **free capability** -- it makes no AI calls, consumes no AI allowance, and works even when every AI provider is disabled.

---

## The health indicator

The indicator lives in the **flow editor header**, right after the word count -- the same widget sheets and scenes use. It counts findings by severity:

| Severity    | Meaning                                                 |
| ----------- | ------------------------------------------------------- |
| **Error**   | Invalid configuration -- the flow cannot run as authored |
| **Warning** | Incomplete or risky authoring                           |
| **Info**    | Valid, but the node will do nothing at runtime          |

When a flow has no findings at all, the indicator collapses to a green check.

Open it to see the findings grouped by **location** -- the flow itself, or one node -- so a node with three problems is one entry with three lines under it. Selecting a node entry **centers the canvas on that node**, highlights it, and selects it. Findings that belong to the flow rather than to a node (no Entry node, several Entry nodes) are listed but not clickable, because there is nowhere to jump to.

Health recomputes as you edit. There is no analysis to run and no snapshot to refresh: what you see is always current, and a finding disappears the moment the underlying problem is gone. There is nothing to "mark as fixed" -- resolution is derived from the flow itself.

The indicator is part of the normal flow editor. Compact and comparison views do not carry it; open the flow in the editor to review its health.

---

## Graph checks

These need the whole graph -- structure and the targets your nodes point at.

| Finding                                                | Severity | What it means                                                    |
| ------------------------------------------------------ | -------- | ---------------------------------------------------------------- |
| Flow has no Entry node                                 | Error    | Nothing declares where playback starts                           |
| Flow has _N_ Entry nodes                               | Error    | More than one start; reachability is computed from all of them   |
| Connection on a removed output pin: _pins_             | Error    | The pin the connection starts from no longer exists              |
| Connection on an invalid input pin: _pins_             | Error    | The pin the connection arrives at is no longer valid             |
| Jump has no target hub                                 | Error    | The Jump was never pointed at anything                           |
| Jump targets a missing hub                             | Error    | Its target hub is not in this flow any more                      |
| Subflow has no referenced flow                         | Error    | The Subflow node was never pointed at a flow                     |
| Subflow references a deleted flow                      | Error    | The referenced flow is gone                                      |
| Exit has no referenced flow                            | Error    | An Exit in **Flow Reference** mode with no destination           |
| Exit references a deleted flow                         | Error    | The destination flow is gone                                     |
| Node is unreachable from Entry                         | Warning  | No path of connections or jumps leads to it                      |
| Node has no connections                                | Warning  | Isolated on the canvas, in neither direction                     |
| Node has no outgoing connection                        | Warning  | A reachable dead end that is not an Exit                         |
| Output pins without a connection: _pins_               | Warning  | A branch was left dangling -- a condition's False pin, a response |
| Hub "_hub id_" is never reached by connection or jump  | Warning  | Nothing targets the Hub, so nothing can converge on it           |

Findings shown here in _italics_ fill that part in with your own data: the number of Entry nodes, the names of the affected pins, the hub's id. The message names the exact pin or hub, so you do not have to hunt for it on the canvas.

Reachability is **topological**, never symbolic evaluation of your conditions:

- one Entry -- traversal starts there;
- no Entry -- the missing-Entry finding is reported and nothing is claimed about reachability;
- several Entries -- the finding is reported and traversal starts from all of them;
- cycles are valid and traversal is cycle-safe;
- a Jump counts as an edge to its Hub, for both reachability and isolation.

---

## Content checks

These read one node's own data.

| Finding                           | Severity | What it means                                                            |
| --------------------------------- | -------- | ------------------------------------------------------------------------ |
| Stale variable reference          | Error    | A referenced sheet or variable was renamed or removed                    |
| Variable type warning             | Warning  | The value assigned or compared does not match the variable's type        |
| Response assignment type warning  | Warning  | The same mismatch inside a dialogue response                             |
| Missing dialogue text             | Warning  | The dialogue node has no line                                            |
| Missing dialogue speaker          | Warning  | No sheet is set as the speaker                                           |
| Empty dialogue response           | Warning  | A response option with no text                                           |
| Incomplete response condition     | Warning  | A response condition with a rule missing its variable, operator or value |
| Incomplete response assignment    | Warning  | A response assignment left half-filled                                   |
| Incomplete condition              | Warning  | A condition node with an unfinished rule or an empty group               |
| Incomplete instruction assignment | Warning  | An instruction assignment left half-filled                               |
| Condition has no rules            | Info     | The node will always take the same branch                                |
| No instruction assignments        | Info     | The node will change nothing                                             |

---

## What the checks do not prove

Every finding states a fact about your data. None of them reads your intent, and several are narrower than they look. Knowing where each check stops is what keeps a finding useful instead of reading as an accusation.

| Check                                | What it does **not** do                                                                                |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| Flow has no Entry node               | Checks node types only; it does not judge where the story should start.                                 |
| Flow has several Entry nodes         | Reachability is computed from all entries; it does not decide which entry is correct.                   |
| Node is unreachable from Entry       | Topological only: conditions are not evaluated, so a reachable node may still be unreachable in play.   |
| Node has no connections              | Counts valid connections and jump links only; it does not know if the node is a draft kept on purpose.  |
| Node has no outgoing connection      | Does not evaluate conditions; an intentional ending modeled without an Exit node still triggers this.   |
| Output pins without a connection     | Reports unconnected required pins; it cannot tell whether the branch is unfinished or abandoned.        |
| Connection on a removed output pin   | Compares stored connections against current pins; it cannot recover what the removed pin meant.         |
| Connection on an invalid input pin   | Compares stored connections against current inputs; it cannot recover the original intent.              |
| Hub is never reached                 | Only in-flow connections and jumps are considered; hubs used by other means are not detected.           |
| Jump has no target hub               | Checks the stored target id only.                                                                        |
| Jump targets a missing hub           | Hubs are matched by id within this flow only.                                                            |
| Subflow has no referenced flow       | Checks the stored reference only.                                                                        |
| Subflow references a deleted flow    | Checks flow existence in this project; it does not inspect the referenced flow's content.               |
| Exit has no referenced flow          | Checks the stored reference only.                                                                        |
| Exit references a deleted flow       | Checks flow existence in this project; it does not inspect the referenced flow's content.               |

Content checks are literal in the same way: an empty dialogue line is reported whether it is a placeholder or a deliberate silent beat, and a type warning compares declared types, not the value that will exist at runtime.

---

## Across the whole project

The **Flows dashboard** lists every finding of every flow in the project under **Issues**, errors first, then warnings, then info. Each row carries its own severity icon and names its location -- the flow, plus the node when the finding belongs to one. Following a row opens that flow; when the finding belongs to a node, it also **focuses that node on the canvas**, so you land on the problem instead of on a canvas you still have to search.

It is the same catalog with the same wording: the dashboard cannot report a problem the editor hides, or hide one the editor reports. The **project dashboard** rolls the same findings up one more level, one line per flow -- errors and warnings only, since an info finding is not something the project owner has to act on.

Dashboard results are cached briefly rather than recomputed on every keystroke, so a finding you just fixed can linger there for a few seconds while the editor's own indicator is already up to date.

---

## Scope

Findings are informational and always derived. There is no way to dismiss, snooze or acknowledge one: the only way to clear a finding is to change the flow so it no longer holds. Whole-project semantic analysis, condition satisfiability, and narrative-quality scoring are out of scope by design.
