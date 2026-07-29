# Slice 7.1a.1 — The platform can be asked, and it answers

**Status:** in progress across reviewable PRs. PR-1, the health consolidation,
merged as [#52](https://github.com/adnumaro/storyarn/pull/52), and PR-2
(`ENG-40`) merged as [#66](https://github.com/adnumaro/storyarn/pull/66).
PR-3 is tracked by `ENG-44`. No AI belongs anywhere in this slice. It builds the
substrate every later palette capability plugs into, including the AI door in
7.1a.2.

## Objective

Make the command palette able to answer questions about the project, through a
typed language the designer can write directly, and make the deterministic
knowledge the platform already holds reachable from it.

A designer should never have to think _"where did X happen"_, _"where is the sheet
for Y"_, or _"where is the option to do Z"_. This slice removes the first and third
for the cases that need no model.

## Delivery plan

This document is the product contract for the whole capability, **not the scope
of one pull request**. The implementation-start audit confirmed that the original
68–97 hour estimate crosses too many data, UI, grammar and migration boundaries
to review safely as one change. Delivery is therefore:

| PR   | Scope                                                                                                                                                                               | Status                                  |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| PR-1 | Health consolidation: one finding contract/catalog per domain, complete project sweeps, editor/dashboard agreement and uncapped cross-domain unused-variable detection              | **Merged as #52**                       |
| PR-2 | `ENG-40`: operation catalog, generated help and guided door, limited to `goto`, `create`/`delete`, `run_command` and `open_view`                                                    | **Merged as #66**                       |
| PR-3 | `ENG-44`: lookup/reference operations (`variable_definition`, `variable_usages`, `entity_usages`, `flow_callers`) and the reference-pattern door                                    | **In progress**                         |
| PR-4 | Authorized normalized `findings`, `incomplete` and `localization_gaps` operations; `missing_exit`, `inescapable_cycle`, `uncalled_flow`; convert-unused-variable-to-constant action | Pending after PR-3                      |
| PR-5 | Cross-domain full-text `content_search`, including its index, bounded query API and write/repair lifecycle                                                                          | Pending after PR-4; independently sized |

PR-2 must not quietly absorb a later row because an existing backend API makes
one operation look cheap. In particular it ships no pattern parser, reference
lookup, project health sweep, localization query, new deterministic rule or
content index. PR-3's pattern work covers the dotted reference forms; quoted
content becomes executable only with PR-5's `content_search`.

## Why this shape

Four separate goals collapse into one piece of infrastructure — an operation
registry:

1. it is what the guided door inserts templates from;
2. it is the generated help surface, so "what can I do here" can never go stale;
3. it is what the natural-language door in 7.1a.2 translates _into_;
4. it is the completeness check that makes **hiding the sidebars** viable for
   advanced users later. That is a hard invariant: an action absent from the
   registry becomes unreachable the moment chrome is hidden.

Because Storyarn is a control center rather than an authoring format, the registry
is deliberately **not scoped to narrative content** — it spans every domain the
product covers. It is also the only structure that can span domains without
becoming a god component.

## The user-facing language

Two doors over one registry. The **guided door** is the default and carries every
operation; the **pattern door** is the expert shortcut. A free-text verb grammar was
considered and **rejected** — see the note at the end of this section.

### The guided door: pick an operation, fill its parameters

Type a word, the palette lists matching operations, you select one, and the
**structure is inserted with a placeholder per parameter**. Focus lands on the first
placeholder with its own completion source — entity types in one, sheet shortcuts in
another — and advances as each is filled.

```
usages of ▮{variable}▮        ← inserted, focus on the parameter
usages of mc.jaime.health     ← after completion
```

Because structure is inserted rather than typed, **a syntax error is impossible** and
nothing has to be parsed. That is also why this door is cheaper than a grammar for
verbs: no error recovery over half-typed input, no per-locale tokenization.

Interaction rules, each of which exists to stop the user getting lost:

- **each parameter is atomic.** Deleting inside a filled parameter clears _that
  parameter_ and returns focus to it, placeholder restored. The input can never hold
  broken syntax, and correcting one parameter never costs the others. Wiping the whole
  template on any deletion was considered and rejected: correction is the most
  frequent user action, and punishing it is exactly what makes a tool noticeable.
- **the template is atomic too.** Backspace at its start, or Escape, removes it whole.
  The exit exists, as one deliberate gesture rather than a side effect of editing.
- **an empty required parameter is not an error.** Enter moves focus there and
  highlights it, silently. An error banner is the opposite of invisible.
- **a filled but invalid parameter IS an error** — a variable that does not exist, a
  deleted sheet. That is information the user cannot deduce, so it is shown.
- **arrow keys navigate results outside a template and parameters inside one.** Two
  keyboard models in one surface is the real implementation risk of this door and it
  needs explicit tests, including IME and screen-reader behaviour.

### Two representations of one operation

What is inserted is **phrase notation**; the registry id is **call notation**, and the
user never sees the second:

```
variable_usages(variable)     internal — registry id, executor API, what 7.1a.2 targets
usages of {variable}          inserted — what the designer picks, reads and corrects
```

`{variable}` is a rendered slot, not literal braces anyone types. The designer never
types `of`, a brace, a paren or a comma — the phrase arrives whole. So it **reads** like
natural language while **behaving** like a widget: a fixed phrase that is chosen, not
composed, which is exactly why it needs no grammar.

Once nobody types the structure, notation is purely a readability decision, and the
phrase wins in all three places it is read: the operation list while choosing, the
generated help with its example, and the filled input while reviewing before Enter.
Parens buy nothing in exchange, and a phrase localizes where
`find_variable_definition` cannot.

### The pattern door: type a reference directly

Dotted references are already the platform's universal vocabulary — condition nodes,
instruction nodes and every variable input display `{sheet_shortcut}.{variable_name}`.
A designer reads them all day, so typing one is muscle memory, not a syntax to learn.

```
mc.jaime.health          this variable
sheets.**.health         any sheet, variable named health
sheets.**.?heal          any sheet, variable name containing "heal"   (ILIKE)
mc.jaime.?               every variable on this sheet
```

A bare pattern means **show me these** — the common case, no verb, no template.
Reference operations and patterns are scoped to the project currently open in
the palette. The project comes from the authenticated LiveView session, never
from a client parameter; outside a project the catalog remains discoverable but
the operations are disabled with an explicit reason.

**Both doors must coexist.** If the input opens with a dotted reference, no template
fires; if it opens with an operation word, the guided door does. Making the template
the only path would kill the expert user the product is trying to create.
Normal destination search also continues in parallel with a ready pattern, so a
dotted sheet shortcut or a multi-word title is never hidden merely because it
resembles reference syntax.

### Identifiers and content must look different

Matching a _name_ and matching _prose inside nodes_ are different searches over
different indexes, and a syntax that blurs them will be misread forever:

```
?heal                    identifier: variable names containing "heal"
"se une al equipo"       content: text inside dialogue, block values, annotations
```

### Why no free-text verb grammar

`def of mc.jaime.health` parsed from raw text was specified and then dropped. It is
the expensive, low-value middle: it needs interactive error recovery, ambiguity rules
for names containing spaces, and per-locale keyword tokenization — while delivering
only marginal speed over the guided door for users who already know the operation
exists, and nothing at all for users who do not.

What survives from the grammar work is the **pattern door only**, which is a small
extension of a grammar that already exists.

**Existing infrastructure:** `assets/app/plugins/expression-editor/` ships a Lezer
grammar whose `VariableRef { Identifier ("." Identifier)+ }` is exactly the dotted
form, an autocomplete that completes sheet shortcuts, variable names and table
row/column paths, a `useCodeEditor` composable, and a build step (`just js-grammar`).
Genuinely new: the `**` wildcard, the `?` ILIKE form, and quoted content.

### Localization

Operation labels, parameter names, descriptions and examples are translated strings
in the registry — **the grammar is not involved at all**, which is what makes this
door cheap to localize. Punctuation (`**`, `?`, quotes) stays neutral, consistent
with the expression editor's code mode already being symbolic while its builder
mode's dropdowns are fully translated.

## Help is a view of the registry, not a document

The palette must answer "what can I even do here". Hand-written help rots; help
generated from the registry cannot.

- **The empty state IS the help.** Opening the palette without typing shows the
  operations grouped by domain — navigation, health, localization, actions — beside
  recents. A terminal needs `help` because it has nowhere to show anything; a palette
  has a panel.
- **`help` still works**, as a keyword, because people type it out of habit. It leads
  to the same place. One surface with grouping, not two overlapping lists.
- **Every entry carries three fields**: description, a **filled example**, and the
  pattern equivalent when one exists. The example teaches more than the description,
  and the pattern column is where a user learns the expert door by osmosis.
- **Selecting from help inserts the template** with focus on the first parameter.
  Help is an alternate entry point to the same flow, never a dead end.
- **The catalog is canonical; availability is contextual.** An operation remains
  discoverable when the current actor or surface cannot execute it, but is disabled
  with a concrete reason such as "No editable projects" or "No commands in this
  view." Authorization is still enforced independently by the server. A dead-end
  template followed by a generic empty state is not an availability explanation.
- **The filter searches descriptions, not just names.** This is how "where is the
  option to do Z" is answered when the user's words differ from ours: typing
  "translate" surfaces `localization_gaps` through its description. Descriptions are
  therefore a **search surface**, written the way a designer would say it — that is
  the curatorial cost of this slice, and it is deliberate.
- **Not** a second command system. No `help <topic>`, no prose pages; prose
  documentation lives in the docs site.

## The operation registry

Every capability is one entry: an id, typed parameters with their completion
sources and client/server delivery mode, a latency class, an authorization
requirement, whether it needs active project context, a result type, and its
**help payload** (description, filled example, pattern equivalent). Help being part
of the entry rather than a separate file is what keeps it from drifting. The
palette is a **router** over it, never a special case per feature.

Latency classes matter because they are a contract, not documentation. The
instant class has a **budget of 150 ms** and a test that fails when it regresses —
above that threshold the tool stops feeling like an extension of the hand, which
is the entire point of the slice.

Client-backed completions filter immediately. Server-backed completions share the
root search's 200 ms debounce so typing cannot amplify the authorization lookup;
the 150 ms instant budget measures the request and adapter after that debounce.

Results **append below, never reorder above the selection.** The current list stays
mounted while a request is in flight. A reply reconciles surviving items in their
existing order, appends new items and preserves the highlighted id when it still
exists. A late result that reshuffles the list while someone is pressing enter
makes them open the wrong thing.

Operation analytics contain only the closed operation id and surface. Selection,
successful completion and abandonment are distinct events; parameter values,
queries, labels and authored content are never included. Recents likewise represent
successful operations, not a failed request or a destructive action abandoned at
confirmation.

### Operations in this slice

Backed by data that already exists:

| Operation                   | Answers                                                  | Delivery |
| --------------------------- | -------------------------------------------------------- | -------- |
| `goto`                      | sheets, flows, scenes, projects by name                  | PR-2     |
| `variable_definition`       | which block defines this variable                        | PR-3     |
| `variable_usages`           | where it is read / written, including formula bindings   | PR-3     |
| `entity_usages`             | backlinks for any entity                                 | PR-3     |
| `flow_callers`              | which subflow/exit nodes reference this flow             | PR-3     |
| `findings`                  | structural + sheet/scene health findings in a scope      | PR-4     |
| `incomplete`                | empty dialogue text, empty blocks, missing localizations | PR-4     |
| `localization_gaps`         | untranslated text in a scope                             | PR-4     |
| `create` / `delete`         | mutating, reauthorized per call                          | PR-2     |
| `run_command` / `open_view` | the capability index itself                              | PR-2     |

Needs one new index:

| Operation        | Answers                                                          | Delivery |
| ---------------- | ---------------------------------------------------------------- | -------- |
| `content_search` | full-text over dialogue text, block values and scene annotations | PR-5     |

That index is the only substantial new infrastructure in the slice, and it is the
gap that makes "the scene where Anna joins" unfindable today: the existing global
destination search matches **names and shortcuts only**. The removed Screenplays
tool is deliberately absent from the index; there are no screenplay elements in
the current product.

## The health work, reframed

`findings` and `incomplete` need one answer shape across domains. Sheets and
Scenes already had one canonical health contract per domain; flows previously had
three shapes and lost most of their analysis on the way out. PR-1 corrected that:
all three domains now expose their complete canonical findings, and the flow
editor and dashboard consume the same composition point. Dashboard numbers
changed as reference-integrity errors started counting; that was the correction,
not a regression.

PR-4 therefore does **not** repeat a health consolidation. It builds the
authorized, bounded cross-domain operation adapter over the merged contracts and
adds only the three genuinely new rules below.

Decision REVERSED in PR-1 — recorded here because the reasoning changed, not the
goal:

- **"one contract, two catalogs" is now one contract, one catalog.** The plan kept
  structural and reference-integrity codes in a frozen rules catalog — versioned,
  fingerprinted, dismissible — separate from the per-node editorial checker, and
  rejected merging them on the grounds that fingerprints and dismissals are
  defined only for structural rules. Slice 7.1a.0 removed the AI explanation and
  PR-1 removed the dismissal lifecycle, which deleted both consumers of the
  fingerprints and of the rule versions. With nothing left to anchor to an exact
  occurrence, the only argument for two catalogs was gone, and keeping them was
  paying for a split that bought nothing.
  All 27 codes now live in one `@severity_by_code` in
  `Storyarn.Flows.HealthChecker` (15 structural, 12 editorial), with `finding/2`
  as the only constructor — identical to `Sheets.HealthChecker` and
  `Scenes.HealthChecker`, neither of which ever had fingerprints or dismissals.
  Detection stays split by what it needs (`HealthChecker` reads one node,
  `StructuralAnalysis` reads the graph); the vocabulary and the severities are
  owned in one place. This is what makes it impossible for the editor and the
  dashboard to word the same finding differently, which was the point of the
  split in the first place.

## The four deterministic rules

They exist so `incomplete` and `findings` have something worth returning.

1. **`missing_exit`** — flow-level, **warning** not error. A flow reached as a
   subflow may legitimately end by falling off its last node; forcing an exit would
   be a behaviour change rather than a lint.
2. **`inescapable_cycle`** — a cycle from which no exit is reachable. The only rule
   with real algorithmic content: reverse reachability over the adjacency,
   including virtual jump→hub edges. **One finding per trapped region**, keyed on
   its lowest node id — per-node would emit twenty findings for a twenty-node loop.
   Must not fire when the exit is reachable only through a jump.
3. **`uncalled_flow`** — no subflow node and no flow-reference exit points at it.
   The lookup already exists; **the cost is noise, not code**. Root flows
   legitimately have no caller, so "entry point" is derived from having no parent in
   the tree — zero new state — and the rule is **validated against Veilbreak before
   it ships. If it is noisy there, it is not ready.**
4. **Unused variables** — already detected and corrected in PR-1. The old ten-row
   cap is gone, and the check already unions flow, scene-zone and scene-pin
   references. The only remaining product work here is the authorized
   **convert-to-constant** action; the union coverage remains as a regression
   test.

Vocabulary note (**corrected — the original claim was wrong**): there are **three**
exit modes, not two. `lib/storyarn_web/live/flow_live/nodes/exit/node.ex:16`
declares `~w(terminal flow_reference caller_return)`, and `caller_return` is live
end to end — the evaluator pops the call stack
(`flows/evaluator/node_evaluators/exit_evaluator.ex`), the Ink, Yarn and Dialogic
exporters each emit it, and the Yarn importer produces it. The spelling
`back_to_caller` never existed; the mode does.

This does not change rule 3's detection. `uncalled_flow` asks who points AT a flow
— a subflow node, or an exit in `flow_reference` mode — and a `caller_return` exit
points at no one by design: switching an exit to that mode clears
`referenced_flow_id` (`node.ex:152-156`), because the destination is whoever called
it at runtime. What changes is the justification. Returning to the caller is not
merely implicit in a terminal exit; it is a mode the author selects. So a flow
containing a `caller_return` exit is stated evidence that the author intends it to
be called as a subflow, which makes an uncalled one a stronger signal rather than a
weaker one. If the rule proves noisy on Veilbreak, that is the first calibration to
try: report uncalled flows that declare a `caller_return` exit, before reporting
the rest.

## Non-goals

- Any model call. If something here needs one, it belongs in 7.1a.2.
- A free-text verb grammar. Rejected above on cost and value; the pattern door is
  the only parsed input.
- Composable/nested queries. Templates are flat by design and the palette is for one
  action at a time; expression building already has its own editor. This is a
  deliberate bet — if palette queries ever need nesting, this door cannot grow into
  it.
- Semantic/embedding search. `content_search` is full-text only; embeddings are a
  later slice behind the same operation.
- Generative analysis (digests, gap narratives) — 7.1a.2.
- Task-manager integrations.
- Actually hiding the sidebars. This slice only makes it _possible_ later.

## Verification / Definition of Done

- ExUnit: every operation authorizes independently; a viewer reaches no mutating
  operation over the socket, asserted by row counts rather than UI state.
- ExUnit: each new rule detected. There is no fingerprint to pin any more — a
  finding is identified by its code plus its location (`entity_type` +
  `entity_id`). `inescapable_cycle` covered for a self-loop, a
  two-node loop, a loop with an unreachable exit, and a loop whose exit is
  reachable only via a jump (must not fire).
- ExUnit: the catalog stays single-sourced — every code the checker can emit has a
  declared severity, and an unknown code raises instead of defaulting to one
  (`test/storyarn/flows/health_consolidation_test.exs`, "the vocabulary is
  single-sourced", which replaced the frozen catalog test when the two catalogs
  were merged; the sheets and scenes coverage tests carry the same pair).
- ExUnit: unused-variable detection unions all three reference sources — a variable
  used only in a scene zone is not reported.
- ExUnit: dashboard and editor cannot disagree for the same flow, including the
  newly surfaced reference-integrity rules.
- **Latency test on the instant class with a 150 ms budget**, on a project seeded to
  realistic size — not on Veilbreak's 93 nodes.
- Vitest: the guided door inserts a template per operation, advances focus on
  completion, clears one parameter without touching the others, and removes the whole
  template only on Escape or backspace-at-start.
- ExUnit/Vitest: the catalog remains canonical while operations unavailable to the
  actor or current surface are disabled with a localized reason and cannot open a
  dead-end template.
- Vitest: an empty required parameter moves focus silently and shows no banner; a
  filled-but-invalid one does show a message. Both directions asserted.
- Vitest: arrow keys navigate results outside a template and parameters inside one,
  with IME and screen-reader coverage.
- Vitest: the pattern door parses every documented form and never fires a template.
- Vitest: a late result never reorders above the current selection.
- ExUnit/Vitest: operation selection, successful completion and abandonment emit
  content-free analytics, and only a successful completion enters recents.
- ExUnit/Vitest: **every registered operation has a description and at least one
  example in en and es** — the test that keeps generated help honest, and that makes
  the sidebar-hiding invariant measurable.
- Vitest: the help filter matches on description text, not only on operation name.
- Vitest: operation labels, parameter names, descriptions and examples resolve per
  locale, and en/es both round-trip through the guided door and help.
- `uncalled_flow` validated against Veilbreak for noise before shipping.
- `mix precommit`, `just quality`, E2E green; changed dashboard counts updated with
  the reason recorded.

## Sizing

The original combined estimate was 68–97 hours. It is retained only as the reason
for the split, not as one implementation commitment. Each pending PR is estimated
again from its then-current `main` before work starts. PR-2 is independently
user-testable: a designer can open the palette, inspect generated help, pick one of
the five delivered operation families and execute it. Every later PR is additive
over that substrate.

## Inputs

The merged deterministic analysis engine and PR-1 health consolidation. The
dismissal lifecycle was removed and is **not an input**. The existing global
destination search (names/shortcuts) and legacy flow-only deep search are not a
cross-domain full-text index. The expression-editor Lezer grammar, autocomplete
and build pipeline remain inputs to PR-3. Existing reference data includes variable
references with read/write kind, sheet backlinks, flow-caller lookup and
cross-flow navigation history. The palette's current nav/create/delete events and
local command registry are the direct inputs to PR-2.
