# Slice 7.1a.1 — The platform can be asked, and it answers

**Status:** specified, not started. No AI anywhere in this slice. It builds the
substrate every later palette capability plugs into, including the AI door in
7.1a.2.

## Objective

Make the command palette able to answer questions about the project, through a
typed language the designer can write directly, and make the deterministic
knowledge the platform already holds reachable from it.

A designer should never have to think _"where did X happen"_, _"where is the sheet
for Y"_, or _"where is the option to do Z"_. This slice removes the first and third
for the cases that need no model.

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

**Both doors must coexist.** If the input opens with a dotted reference, no template
fires; if it opens with an operation word, the guided door does. Making the template
the only path would kill the expert user the product is trying to create.

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
- **The filter searches descriptions, not just names.** This is how "where is the
  option to do Z" is answered when the user's words differ from ours: typing
  "translate" surfaces `localization_gaps` through its description. Descriptions are
  therefore a **search surface**, written the way a designer would say it — that is
  the curatorial cost of this slice, and it is deliberate.
- **Not** a second command system. No `help <topic>`, no prose pages; prose
  documentation lives in the docs site.

## The operation registry

Every capability is one entry: an id, typed parameters with their completion
sources, a latency class, an authorization requirement, a result type, and its
**help payload** (description, filled example, pattern equivalent). Help being part
of the entry rather than a separate file is what keeps it from drifting. The palette is a **router** over it,
never a special case per feature.

Latency classes matter because they are a contract, not documentation. The
instant class has a **budget of 150 ms** and a test that fails when it regresses —
above that threshold the tool stops feeling like an extension of the hand, which
is the entire point of the slice.

Results **append below, never reorder above the selection.** A late result that
reshuffles the list while someone is pressing enter makes them open the wrong
thing.

### Operations in this slice

Backed by data that already exists:

| Operation                    | Answers                                                  |
| ---------------------------- | -------------------------------------------------------- |
| `goto`                       | sheets, flows, scenes, projects by name                  |
| `variable_definition`        | which block defines this variable                        |
| `variable_usages`            | where it is read / written                               |
| `entity_usages`              | backlinks for any entity                                 |
| `flow_callers`               | which subflow/exit nodes reference this flow             |
| `findings`                   | structural + sheet/scene health findings in a scope      |
| `incomplete`                 | empty dialogue text, empty blocks, missing localizations |
| `localization_gaps`          | untranslated text in a scope                             |
| `create` / `delete`          | mutating, reauthorized per call                          |
| `run_command` / `open_panel` | the capability index itself                              |

Needs one new index:

| `content_search` | full-text over dialogue text, block values, scene annotations, screenplay elements |

That index is the only substantial new infrastructure in the slice, and it is the
gap that makes "the scene where Anna joins" unfindable today: the existing global
search matches **names only**.

## The health work, reframed

`findings` and `incomplete` need one answer shape across domains. Sheets and
Scenes already have one canonical health contract per domain; flows have three
shapes and lose most of their analysis on the way out — the dashboard mapping
collapses 15 canonical rules into 3 coarse buckets, discarding every
reference-integrity error, invalid pin and orphan hub.

So the normalization lands here, but as the **backend of an operation the designer
invokes**, not as internal tidying. Same work, a reason the user can feel.

Decisions carried over unchanged:

- **one contract, two catalogs** — structural and reference-integrity codes stay
  owned by the frozen rules catalog (versioned, fingerprinted, dismissible);
  editorial codes stay owned by the per-node health checker. Merging is rejected:
  fingerprints and dismissals are defined only for structural rules;
- dashboard numbers **will change** as reference-integrity errors start counting.
  That is the correction, not a regression.

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
4. **Unused variables** — already detected. The work is the ten-row cap, a
   **convert-to-constant** action, and a correctness risk: the check must union
   flow, scene-zone and scene-pin references, or a variable used only in a scene
   zone is reported unused.

Vocabulary note: there is **no `back_to_caller` exit mode** — only `terminal` and
`flow_reference`. Returning to the caller is what a terminal exit does implicitly
inside a subflow, so rule 3 is the checkable form of that idea.

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
- ExUnit: each new rule detected; fingerprint stable across an unrelated edit and
  rotated by a relevant one. `inescapable_cycle` covered for a self-loop, a
  two-node loop, a loop with an unreachable exit, and a loop whose exit is
  reachable only via a jump (must not fire).
- ExUnit: the frozen catalog test still fails on a severity or category swap.
- ExUnit: unused-variable detection unions all three reference sources — a variable
  used only in a scene zone is not reported.
- ExUnit: dashboard and editor cannot disagree for the same flow, including the
  newly surfaced reference-integrity rules.
- **Latency test on the instant class with a 150 ms budget**, on a project seeded to
  realistic size — not on Veilbreak's 93 nodes.
- Vitest: the guided door inserts a template per operation, advances focus on
  completion, clears one parameter without touching the others, and removes the whole
  template only on Escape or backspace-at-start.
- Vitest: an empty required parameter moves focus silently and shows no banner; a
  filled-but-invalid one does show a message. Both directions asserted.
- Vitest: arrow keys navigate results outside a template and parameters inside one,
  with IME and screen-reader coverage.
- Vitest: the pattern door parses every documented form and never fires a template.
- Vitest: a late result never reorders above the current selection.
- ExUnit/Vitest: **every registered operation has a description and at least one
  example in en and es** — the test that keeps generated help honest, and that makes
  the sidebar-hiding invariant measurable.
- Vitest: the help filter matches on description text, not only on operation name.
- Vitest: operation labels, parameter names, descriptions and examples resolve per
  locale, and en/es both round-trip through the guided door and help.
- `uncalled_flow` validated against Veilbreak for noise before shipping.
- `mix precommit`, `just quality`, E2E green; changed dashboard counts updated with
  the reason recorded.

## Estimate

| Phase                                                             | Hours     |
| ----------------------------------------------------------------- | --------- |
| 0 Re-verify current state against main                            | 0.5       |
| 1 Operation registry + router + latency classes                   | 8-12      |
| 2 Guided door: template insertion, focus model, atomic parameters | 10-14     |
| 2b Pattern door: grammar extension (`**`, `?`, quotes)            | 4-6       |
| 2c Help view: empty state, grouping, description search           | 5-7       |
| 3 `content_search` index and operation                            | 8-12      |
| 4 Lookup/navigation operations over existing data                 | 6-9       |
| 5 Health contract + `findings`/`incomplete`/`localization_gaps`   | 8-12      |
| 6 The four rules                                                  | 12-17     |
| 7 i18n, latency tests, catalog pinning, dashboard test updates    | 6-8       |
| **Total**                                                         | **68-97** |

Phases 1, 2 and 2c are the substrate and are separable: shipping them with `goto`
and the lookup operations is already user-testable — a designer can open the palette,
see what it can do, pick an operation and be taken somewhere. Everything after is
additive.

## Inputs

The merged deterministic analysis engine and its dismissal lifecycle. The existing
global search (names only). The expression-editor Lezer grammar, autocomplete and
build pipeline. Existing reference data: variable references with read/write kind,
sheet backlinks, flow-caller lookup, cross-flow navigation history. The palette's
current nav/create/delete events and local command registry.
