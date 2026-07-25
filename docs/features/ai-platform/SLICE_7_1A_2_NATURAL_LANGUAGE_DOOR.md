# Slice 7.1a.2 — Asking in your own words

**Status:** specified, not started. Hard dependency on 7.1a.1: there is nothing to
translate into until the operation registry exists.

**Supersedes** the earlier narrative-coherence specification under this number,
which was discarded. That analysis is kept in the memory record for its scale
arithmetic; the feature is not planned.

## Objective

Let a designer type a question the way they think it, and have the platform answer
it — while keeping every fact the platform's own.

**Scope narrowed after 7.1a.1's guided door was designed.** With template insertion,
per-parameter completion and generated help, a designer who knows an operation exists
rarely needs to write a sentence. That is the intended outcome — the AI is the on-ramp,
not the engine — but it means this slice earns its cost in exactly two situations:

1. the user **does not know the operation exists**, so no amount of autocomplete helps
   them find it;
2. the question is **analysis**, where no operation can answer because the answer is
   prose.

Everything else is better served by the guided door. If a phrasing in the corpus maps
cleanly to an operation the user could have picked, that is a signal for better help
copy or a better operation label — not for a cleverer prompt.

The AI does exactly two jobs here, and neither is answering questions about data:

1. **Translate** free-form text into one operation from 7.1a.1's registry. The
   platform executes it and produces the result. The model never touches the data.
2. **Compose** an analysis answer — a digest, a gap narrative — from figures the
   platform computed and handed to it. The model phrases, it does not retrieve.

Both modes are hallucination-proof by construction: in translation the model does
not speak, and in composition it can only phrase what it was given.

## Why this is the anchor, not a feature

Every AI capability planned after this — character lore, chapter summaries,
"is ticket X done?", task-manager integrations — enters as **one more operation in
the registry**, with no change to the palette, the grammar, or the translation
layer. This slice is what makes that true. Building generative capabilities before
it means each one arrives as its own surface.

## Translation

Free text in, one registry operation out, as schema-validated structured output
against a closed catalog. Not text-to-query: the model selects an operation and
fills typed parameters, so its only possible error is **intent**, never fact.

### Resolve into the guided door, do not answer past it

Translation output is **the same template the guided door would have inserted**, with
its parameters filled. The user sees the operation and its values, in the exact form
selecting it manually produces, and can correct any parameter with the same gesture as
anywhere else. There is no separate AI result surface and no second execution path.

This is what makes the AI a ramp rather than a parallel system: a translated query and
a hand-picked one are indistinguishable downstream.

Showing a generated query is prohibited, and not for cosmetic reasons: it teaches a
false mental model in which the model has database access and writes arbitrary
queries. That invites trusting precisely what must never be trusted. A named
operation with typed parameters is honest about the real capability surface — the
model can only pick from a list.

### Ask for the missing parameter, never guess

When a required parameter cannot be filled, the surface asks for that parameter and
nothing else. A confident answer to a misunderstood question is the worst failure
mode this design can have, and asking is what removes it.

### On a tie, offer both

_"Where is variable X defined"_ and _"where is X used"_ differ only in read-vs-write
intent. Picking wrong yields a well-formed, wrong-shaped answer. When two
operations score close, the surface **presents both instead of choosing**.

### Latency and cost

Translation output is short — an operation and a few parameters, not prose — so it
belongs to a fast class, and the result is **cached by phrasing**: the same question
stops costing anything after its first use.

It sits in the palette's slow tier and appends below the instant results, never
reordering above the selection. A designer who learns the structured door stops
invoking the model at all, which is the intended outcome: **the AI is the on-ramp,
not the engine.**

### The quality rule

**A question answered generatively when an operation existed to answer it is a
bug.** Without that rule the box degenerates into a chatbot opining over data it was
already holding. It is enforced by the corpus below, not by hope.

## Composition — the only generative surface

Two operations, both fed exclusively with platform-computed data:

| Operation               | Question                          |
| ----------------------- | --------------------------------- |
| `digest(period, scope)` | _"¿qué ha cambiado esta semana?"_ |
| `explain_gaps(scope)`   | _"¿qué falta por implementar?"_   |

Every number and every item in the output comes from `findings`, `incomplete`,
`localization_gaps` and version history — computed by 7.1a.1's operations. The model
receives that structure and writes the paragraph. **It retrieves nothing and must
not be able to.**

This is why a digest is generative even though its inputs are deterministic: prose
is the right output shape for it, and composition is the model's actual competence.

## The labelled corpus is a deliverable, not test scaffolding

Real designer phrasings paired with the operation each should resolve to. It is the
only way to know whether translation works, and it does three jobs:

- measures translation accuracy, per locale;
- **tells us when a new operation is needed** — when several corpus entries have
  nowhere to go;
- catches the quality-rule violation above, by containing questions that must
  resolve to an operation and must never reach composition.

It can and should be started **before any code**, in parallel with 7.1a.1, so the
initial catalog is designed against real questions rather than my guesses.

## Non-goals

- Character lore, chapter summaries, ticket verification, Jira/Trello integration.
  All are later operations behind this same layer — deliberately not bundled, since
  each carries its own context and authorization design.
- Semantic/embedding search. It belongs behind 7.1a.1's `content_search` operation,
  as a second strategy when full-text finds nothing, and needs no model.
- Any generative output that asserts a state the platform did not compute.
- Mutating operations reached through translation without an explicit confirmation
  step.

## Verification / Definition of Done

- ExUnit: translation output is validated against the registry; an operation id
  outside it, or a parameter of the wrong type, is rejected before execution.
- ExUnit: a missing required parameter produces a question, never a filled default.
- ExUnit: composition operations receive only platform-computed input — asserted by
  giving the model no retrieval capability in the task contract, and by a test that
  a figure absent from the input cannot appear in the output.
- ExUnit: mutating operations reached by translation require confirmation; a
  translated `delete` never executes on the first turn.
- ExUnit: translation results are cached by normalized phrasing, and a cache hit
  performs no provider attempt — asserted by usage-event count.
- Corpus: measured accuracy per locale, with the threshold recorded in the PR and
  the failures listed rather than hidden.
- Corpus: every entry that should resolve deterministically does, proving the
  quality rule.
- Vitest: translation produces the same template the guided door inserts, and its
  parameters are correctable with the same gestures; no query string is ever shown,
  asserted negatively.
- Corpus: entries that map cleanly to a pickable operation are reported as help-copy
  gaps rather than counted as translation wins.
- Vitest: translated results append below instant results and never reorder above
  the selection.
- Browser: one managed run against a real provider, plus the exhausted-allowance and
  translation-failure paths.
- `mix precommit`, `just quality`, E2E green.

## Estimate

| Phase                                                                 | Hours     |
| --------------------------------------------------------------------- | --------- |
| 0 Re-verify the registry contract and kernel refs                     | 0.5       |
| 1 Corpus (startable before 7.1a.1 lands)                              | 4-6       |
| 2 Translation task: contract, prompt, structured output, validation   | 10-14     |
| 3 Palette integration: operation display, clarification, tie handling | 8-12      |
| 4 Phrasing cache                                                      | 4-6       |
| 5 `digest` + `explain_gaps` composition                               | 8-12      |
| 6 Tests, accuracy measurement, i18n                                   | 8-11      |
| 7 Browser verification                                                | 2-3       |
| **Total**                                                             | **45-64** |

Phase 1 is the gate. If the corpus shows most real questions have no operation to
resolve to, the answer is more operations in 7.1a.1 — not a cleverer prompt.

## Inputs

7.1a.1's operation registry with its translated labels, examples and templates, plus
the pattern-door grammar. The AI kernel's
preflight, allowance projection, route options, idempotency and spend guarantees.
Structured-output validation against a declared schema. The deterministic health
and localization operations that feed composition.
