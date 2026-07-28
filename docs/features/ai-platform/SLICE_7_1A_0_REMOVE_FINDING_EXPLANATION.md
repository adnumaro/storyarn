# Slice 7.1a.0 — Remove the structural-finding AI explanation

**Status:** implemented on `codex/slice7-1a-0-remove-finding-explanation`. Slice 7.2a
merged first, unchanged (PR #49). This PR lands before 7.1a.1 begins.

**Four things the inventory below did not anticipate**, all found by the
grep-to-zero and Kept-table checks rather than by reading:

1. `context_test.exs` had ~10 sites bound to the structural scope, and
   `context_source_locks_test.exs` was built entirely on it. The latter tests
   generic kernel machinery, so it was **rewritten** against `dialogue` and
   `flow_neighborhood` rather than deleted.
2. Removing the scope made `SourceLocks.verify_evidence_entries/2` and
   `Context.EvidenceLoader` unreachable — that re-verification ran _only_ for the
   non-persistable scope, because it was the one that could not be rebuilt from a
   persisted subject. Every surviving scope is checked more strongly one layer up,
   where `Context.operation_current?/3` rebuilds the package and compares hashes.
   No capability was lost; both were deleted as dead code.
3. The DB CHECK constraints on `ai_route_options` and `ai_operations` still named
   `structural_finding`, so the schema would have kept accepting a shape the
   application can no longer produce. A migration narrows both.
4. **Five Kept rows lost all coverage** when the panel's 38 tests went:
   `release_if_unstarted/2`, `created_operation?/3`, the two idempotency-key
   lookups and `record_view/2`. `test/storyarn/ai/kernel_spend_guarantees_test.exs`
   restores it against the fixture task — 14 tests, each verified by breaking the
   production code and watching the right one fail.

## Why a feature that shipped is being removed

Slice 7.2a delivered exactly what it specified and its acceptance criteria are met.
What was discovered afterwards is that the criteria were aimed at the wrong thing:

**the structural analysis of a flow IS the health check, and for all 15 of its rules
the finding is already the explanation.** "Your jump points at a hub that no longer
exists" needs no model. Where an explanation would take real work — _why_ is this node
unreachable — the deterministic engine already holds the answer from its own BFS and
simply does not surface it. That is a gap in the deterministic layer, not a use for a
model.

So the explanation task never earns its cost in front of a user, and 7.1a.1 gives its
answers a better home: `findings` and `incomplete` operations in the palette.

**What 7.2a actually bought stays.** Its reusable deliverable was never the task — it
was the first end-to-end consumer of the AI kernel, and the spend, allowance, config
and diagnostic hardening that came out of four review rounds. That is what 7.1a.2 and
every later AI capability build on. Removing it would be throwing away the asset and
keeping the wrapper.

## Removed

Nothing below has another consumer.

**Task and lifecycle**

- `lib/storyarn/ai/tasks/flow_finding_explanation.ex`
- `lib/storyarn_web/live/flow_live/handlers/explanation_handlers.ex` and its dispatch
  in `flow_live/show.ex`, including the `release_on_teardown/1` call in `terminate/2`
- Facade entries: `flow_finding_explanation_registered?/0`, `_intent/2`, `_key/4`,
  `_task_id/0`, `flow_finding_explanations_ready/2`
- Task registration in `config/runtime.exs` and `config/test.exs`

**Context (owner decision: remove)**

- `lib/storyarn/ai/context/builders/structural_finding.ex`
- the `:structural_finding` kind in `SubjectRef`, its non-persistable branch and its
  `valid_finding?` clauses

Slice-6 code with no remaining consumer. Dead code carrying a security surface is
worse than a smaller catalog.

**The explanation-ready badge** — added late in 7.2a and only for this feature

- `Results.readable_subject_revisions/3` and the
  `ai_operations_actor_task_subject_revision_index` migration
- `hasExplanation` in `AnalysisHandlers.finding_props/3` and `explained_identities/2`
- the Sparkles marker in `FlowAnalysisFindingCard.vue`, its type field and
  `flows.analysis.has_explanation` in both locales

**Surface**

- `FlowAnalysisExplanation.vue`, the `FlowExplanationState` type, the panel wiring in
  `FlowAnalysisPanel.vue`, and the selection/eligibility gate that registered the
  palette command
- the whole `flows.explanation.*` tree in `en` and `es`, including the
  `retention_hours`/`retention_minutes` pair and every error-class string

**Tests**

- `test/storyarn_web/live/flow_live/handlers/explanation_handlers_test.exs` (38 tests)
- `test/storyarn/ai/tasks/flow_finding_explanation_test.exs`
- `assets/app/test/.../FlowAnalysisExplanation.test.ts` and the explanation cases in
  `FlowAnalysisPanel.test.ts`
- the explanation steps in `test/e2e/flow_analysis_test.exs` (`explanation-open`
  through `explanation-result`)

## Kept — verify each one still compiles and is still tested

This list is the point of the document. Every item is generic kernel work that a later
AI feature needs, and each is easy to delete by accident while chasing a reference to
the task.

| Kept                                                                                            | Why                                                                                                                                                                                    |
| ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Operations.release_if_unstarted/2`                                                             | any surface abandoning an operation; decides under the row lock                                                                                                                        |
| `RouteOptions.created_operation?/3`                                                             | the only reliable "did I buy this operation" answer                                                                                                                                    |
| `Results.get_by_idempotency_key/3`, `operations_by_idempotency_keys/3`                          | attempt resolution and replay                                                                                                                                                          |
| `Operation.viewed_at`, `viewed_changeset/1`, `Results.record_view/2`, `AI.record_result_view/2` | **owner decision: stays.** Generic "the actor saw this result"; 7.1a.2's analysis results will want it. The `record_result_view` call sites go with the panel; the capability does not |
| Allowance projection during preflight                                                           | every managed task needs it                                                                                                                                                            |
| `bool_env`, `decimal_env`, `positive_decimal_env`, price/cap boot validation                    | config correctness, unrelated to the task                                                                                                                                              |
| Single-source `REDIS_URL`, deleted `ADMIN_EMAIL`                                                | same                                                                                                                                                                                   |
| Fake provider `enum` clause + `Map.has_key?` schema default                                     | operator diagnostics report the managed path honestly                                                                                                                                  |
| `Finding.decode_identity/1` UTF-8 + printable guard                                             | deterministic, in Flows                                                                                                                                                                |
| `Shared.CanonicalJSON`                                                                          | shared utility, registered                                                                                                                                                             |
| `OBAN_AI_QUEUE_HARDENING.md`, `SHARED_HELPER_EXTRACTIONS.md`                                    | deferred work, still owed                                                                                                                                                              |
| `GETTEXT_EXTRACTION_DEBT.md`                                                                    | closed by ENG-32; the doc is gone and its rules live in `docs/conventions/domain-patterns.md`                                                                                          |

**Open question for implementation:** `Flows.fetch_current_structural_finding/3` and
the identity encode/decode pair lose their only caller here, but 7.1a.1's `findings`
operation plausibly wants a stable finding identity for deep-linking. Decide when
7.1a.1's operation shapes are settled; until then, keep them and mark them.
**Resolved:** kept, and marked at both the facade and
`StructuralAnalysis.fetch_current_finding/3` with the caller status, the reason and
the condition for deleting them. `release_if_unstarted/2` and `created_operation?/3`
carry the same marker for the same reason.

## What the audit caught after the implementation was "done"

Owner audited the finished branch. Every gate was green and re-verified — ExUnit
8291/0, E2E 64/0, Vitest 767/767, credo, format, `compile --warnings-as-errors`,
vue-tsc, knip — and four leftovers survived all of them. **The Kept-table loop
protects what stays; nothing was checking that what should go actually went.**

1. **A Removed row that was never removed.** `Results.readable_subject_revisions/3`
   was still in `lib/`, with no caller and no test, while this document listed it
   under Removed _and_ the migration dropping its index asserted in its own comment
   that the function was gone. Deleted now, which makes both statements true.
   **Loop the Removed table exactly like the Kept table: grep every row, investigate
   every non-zero hit.** A removal document is a claim until something checks it.
2. **`pnpm run lint` was never run** and was red: four imports orphaned where the
   deleted code used to use them. `mix format`, credo, knip and vue-tsc all pass
   through unused imports. Removals are exactly what oxlint catches.
3. **Gettext drifts in the removal direction too.** Deleting a module leaves its
   msgids in the `.pot` and every `.po`; the parity guard compares those to each
   other, never to the source, so it stays green while pointing at a deleted file.
   `flows` was the one fully-extracted domain and this PR dirtied it. Fixed with
   `gettext.extract --merge`, reverting every domain but `flows`.
4. **A dynamic i18n key survived every symbol grep.**
   `integrations.context_disclosure.scopes.structural_finding` lived on in `en` and
   `es` because `ContextDisclosure.vue` builds the key by interpolation. **Grep the
   removed string values, not only module and function names.**

Also corrected: a moduledoc still naming the deleted feature as its live consumer,
a test comment citing the wrong function for coverage it defers to, and two Kept
documents (`SHARED_HELPER_EXTRACTIONS.md`, `OBAN_AI_QUEUE_HARDENING.md`) whose
call-site citations had become dead references.

## Consequences elsewhere

- **`SLICE_7_2A_MANAGED_EXPLANATION.md`** gets a status note: implemented, ACs met,
  superseded by this removal, with the reason. An implemented feature deleted without
  a written reason looks like a mistake to whoever reads it next.
- **`SLICE_7_2B_PERSONAL_LANE_AND_DOCS.md`** loses its premise — it was the personal
  lane and public docs _for this task_. It must be re-pointed at whatever becomes the
  first real AI feature, which is 7.1a.2's translation layer. Re-scoping is not part
  of this PR; flagging it is.

## Verification / Definition of Done

- `mix test`, `pnpm run test`, `mix test.e2e` green with the counts down by exactly
  the removed tests and no other change.
- `mix compile --warnings-as-errors` clean — no orphaned aliases or unused functions.
- `mix credo --strict`, `vue-tsc`, `mix format`, `oxfmt` clean.
- **`pnpm run lint` clean** — the only gate that sees an import left dangling by a
  deletion.
- **`mix gettext.extract --merge`, then revert every domain but the one this PR
  touches** — deleting a module with user-facing strings orphans msgids that the
  `.po`↔`.pot` parity test cannot see.
- **Every row of the Removed table greps to zero**, in `lib/`, `test/`, `priv/` and
  `assets/` — including the removed _string values_ (context scopes, destination ids,
  i18n keys built by interpolation), not just module and function names.
- Zero grep hits for `flow_finding_explanation`, `explanation_handlers`,
  `structural_finding` context, `hasExplanation` or `flows.explanation.` outside this
  document and the 7.2a spec's historical note.
- `pnpm knip` reports no newly-unreferenced modules.
- The locale files parse and the en/es key-parity test passes after the tree removal.
- **A test still covers each row of the Kept table.** If removing the task orphans a
  kernel test, the test is rewritten against a fixture task — not deleted.
- The managed operator diagnostic still reports `ok` against the fake with no scenario.

## Estimate

| Phase                                                                | Hours    |
| -------------------------------------------------------------------- | -------- |
| 0 Re-verify the inventory against merged main                        | 0.5      |
| 1 Remove task, lifecycle, facade, config registration                | 2-3      |
| 2 Remove context builder and SubjectRef kind                         | 1-2      |
| 3 Remove badge, surface, i18n tree                                   | 2-3      |
| 4 Test cleanup, rewrite orphaned kernel tests against a fixture task | 2-3      |
| 5 Doc status notes (7.2a, 7.2b flag) and gate run                    | 1        |
| **Total**                                                            | **8-12** |

## Inputs

Merged Slice 7.2a. The reasoning that led here is recorded in the AI feature
value map and the palette control-surface design; this document is the executable
inventory, not the argument.
