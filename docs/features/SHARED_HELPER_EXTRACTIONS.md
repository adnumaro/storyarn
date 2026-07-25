# Shared helper extractions

**Status:** not done. Split out of the Slice 7.2a audit remediation by owner
decision (2026-07-25). The audit's other duplication findings landed in
`31ebb29e`; these three refactor code the slice does not own, so they belong in
their own PR with their own verification.

**Measured against:** `codex/slice7-2a-managed-explanation` at `31ebb29e`.

## Why these three are different

Every other duplication finding was local: one file, or two files in the same
directory, with the slice owning both sides. These three each require changing
call sites in **other domains** — scenes, sheets, workspaces, the debug session,
the versioning snapshot path. A feature branch that also refactors those is
unreviewable, and a regression in them would be attributed to the AI explanation
work.

Each one is independently landable. Do them in the order below; none depends on
another.

---

## 1. `LiveTimer` — cancel-then-reschedule, implemented five times

### Current state

| Where | Ref storage | Token guard | Cancels |
| --- | --- | --- | --- |
| `lib/storyarn_web/helpers/save_status_timer.ex:9` | **no ref** — only `:save_status_reset_token` | ✅ `make_ref()` | never; the guard replaces cancellation |
| `lib/storyarn_web/helpers/auto_snapshot.ex:27,37` | two sibling assigns: `:auto_snapshot_timer` + `:auto_snapshot_ref` | ✅ | ✅ |
| `lib/storyarn_web/live/flow_live/handlers/debug_execution_handlers.ex:180-197` | one assign `:debug_auto_timer` | ❌ | ✅ |
| `lib/storyarn_web/live/flow_live/show.ex:274` | same assign, **re-implemented inline** during debug-session restore | ❌ | ❌ |
| `lib/storyarn_web/live/flow_live/handlers/explanation_handlers.ex` | **process dictionary** (`@timer_key`) | ❌ | ✅ |

The explanation handler is the odd one out on purpose: `show.ex` passes the whole
`assigns` to its prop builders, which strong-taints the template, so writing a
timer ref into an assign cost a full canvas re-encode per tick (~250 KB at 500
nodes). See commit `36ae9f45`. **That constraint applies to any timer in the flow
editor**, which is the strongest argument for a shared helper: the other two flow
timers still store their refs in assigns.

### What a shared helper must support

1. Ref in the process dictionary by default (the render-cost lesson), with the
   token in the message when the caller wants stale-tick rejection.
2. Optional token: two sites send `{atom, token}` and guard; two send a bare atom
   — and **tests poke the bare atoms directly**
   (`explanation_handlers_test.exs` does `send(view.pid, :poll_explanation)`), so
   forcing tokens everywhere breaks them. Support both or plan the test change.
3. Cancel-then-reschedule as one call; 3 of 5 sites do exactly that.
4. A no-ref variant: `SaveStatusTimer` deliberately allows overlapping timers and
   relies on the token alone. Forcing it to store a ref is a behaviour change.
5. Per-call interval — `debug_execution_handlers` reads `assigns.debug_speed`, not
   a module attribute.
6. Recurring self-rescheduling polls with an independent wall-clock deadline
   (`polling_since` + a configurable deadline). Only the explanation handler has
   this today; leaving it out means keeping two half-mechanisms.

### Verification

Each converted site keeps its existing tests. Add one asserting a timer ref is
**not** in socket assigns for flow-editor timers, with a positive control — a
`refute` over assign contents passes vacuously if the key name is wrong.

---

## 2. `Validations.bounded_text?` — six private validators, two semantics

### Current state

`Storyarn.Shared.Validations` (68 lines) is **entirely Ecto-changeset shaped** —
`validate_shortcut/2`, `validate_email_format/1`, `validate_slug/1`, plus two
regex accessors. It contains no `boolean()`-returning predicate at all, and each
validator hardcodes its field name. Adding a predicate would be the first of its
kind there, so decide deliberately whether it belongs in `Validations` or in a new
`Storyarn.Shared.BoundedText`.

`byte_size` family, all requiring non-empty:

- `lib/storyarn/ai/executor.ex:121-122` — `optional_bounded_string?/2`
- `lib/storyarn/ai/execution_intent.ex:85-91` — `bounded_string/2`, returns `{:ok, value} | {:error, :invalid_string}`, **not** a boolean
- `lib/storyarn/ai/execution_intent.ex:105-106` — inline guards, not a named function
- `lib/storyarn/ai/context/policy.ex:106` — `bounded_string?/1`, **arity 1, max baked in at 120**

`String.length` family:

- `lib/storyarn/versioning/builders/flow_builder.ex:3839-3841` — `optional_bounded_string?/2`, **does not reject `""`**
- `flow_builder.ex:3843-3845` — `bounded_nonempty_string?/2`, non-empty via `String.trim/1`
- `flow_builder.ex:3906-3907` — `valid_snapshot_string?/2`, non-empty via `!= ""`, so whitespace-only passes
- `lib/storyarn/ai/tasks/flow_finding_explanation.ex` — `bounded_text?/1`, **arity 1, max baked in**, `String.length` on purpose to mirror the JSON-schema `maxLength` the model is held to

### The variant matrix any shared predicate must cover

`byte_size` vs `String.length`; required vs `nil`-permitting; non-empty via
`!= ""` vs `String.trim/1` vs not enforced; max as argument vs module attribute;
`boolean()` vs `{:ok, value}` return. **Two sites are arity-1 with a baked-in
max**, so consolidating changes their call shape at 5 places.

Do not unify the two unit semantics. `byte_size` guards transport limits;
`String.length` mirrors a schema contract. A single function taking a unit
parameter is fine; silently switching a caller from one to the other is not.

Also nearby, so you do not add a seventh: `flow_builder.ex:3835`
`nonempty_string?/1`, `:3837` `optional_string?/1`, and `:2248`
`present_string?/1` — which already duplicates `:3835` inside the same file.

---

## 3. `usePaletteCommands` — three idioms across eight call sites

### Current state

There is **no** composable wrapping `registerPaletteCommands`; nothing named
`usePaletteCommands` exists. Composables live in
`assets/app/shared/composables/` (note: `assets/app/composables/` does not exist —
CLAUDE.md's tree is stale on this).

- **(A) `watchEffect` + `onCleanup`**, 11 lines, no mutable local, no
  `onUnmounted` — `modules/flows/editor/components/panels/FlowAnalysisPanel.vue`.
  This is the best of the three and the one to promote.
- **(B)/(C) `let unregister` + `watch(..., {immediate: true})` + `onUnmounted`**,
  25 lines each, structurally identical to each other —
  `live/workspace/dashboard/WorkspaceDashboard.vue:227-251` and
  `live/layouts/workspace/Layout.vue:33-57`.
- **(D) static**, 5 sites: `live/flow/show/FlowHeader.vue:98-107`,
  `modules/flows/editor/components/chrome/FlowMinimapToggle.vue:36-53`,
  `modules/scenes/editor/components/canvas/SceneCanvas.vue:171-181`,
  `live/layouts/CommandPalette.vue:18-28`,
  `live/layouts/project/Layout.vue:131-136`.

### What the composable must handle

The mechanical reason all this churn exists: `registerPaletteCommands(surface,
commands)` takes a **plain array**, captured at registration. `visible?()` and
AI `availability.state` are re-evaluated by the `paletteGroups` computed, but a
changing **label, icon, or closure argument** requires re-registration — which is
why (A)/(B)/(C) exist at all.

Two traps to preserve:

- `paletteGroups` dedups by id and **first registration wins**
  (`registry.ts:74`), so a stale registration outliving its replacement silently
  shadows the new one. The composable must unregister before re-registering.
- (A) registers an **empty array** when ineligible rather than skipping
  registration, keeping `"flows"` an active surface for `primarySurface`. Preserve
  that; it is not an accident.

### Also consider

`registerAIDestination` (`shared/command-palette/aiDestinationRouter.ts`) has the
same unmanaged-lifetime shape but a different contract — last-one-wins with a
token-guarded disposer, and ownership is a convention with no runtime enforcement.
Decide whether one composable covers both or they stay separate; do not assume the
destination behaves like the command registry.

---

## Non-goals

- Anything already landed in `31ebb29e`.
- `track/3` in the two flow analysis handlers. A 3-line wrapper over
  `Analytics.track/3`; importing it across handler modules costs more than the
  duplication.
- The duplicated Gettext msgid the audit flagged. Two call sites of one msgid is
  how Gettext works — the catalog has a single entry.
- Splitting `explanation_handlers.ex` to meet the 200-line limit. Related but
  separate: it needs three modules (presenter / poll mechanics / transitions), see
  `079f4dec`.
