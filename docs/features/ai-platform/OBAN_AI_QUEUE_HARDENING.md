# Oban `:ai` Queue Hardening

**Status:** not implemented. Deferred out of Slice 7.2a by owner decision
(2026-07-25). This file is a specification for a later, self-contained change —
nothing under **Proposed change** exists in the codebase yet.

**Verified against:** branch `codex/slice7-2a-managed-explanation` at
`1355095c`, Oban `2.22.1` (`mix.lock:66`). Every claim below was read from
source; `deps/` citations are to the vendored Oban of that exact version.

> **Slice 7.1a.0 (2026-07-25) deleted two of the files cited here**,
> `explanation_handlers.ex` and `flow_finding_explanation.ex`. The measurements
> taken from them at `1355095c` stand as evidence and are marked **[removed]**
> where they appear; the code is not there to re-read. One consequence is
> material rather than editorial: **no registered task enqueues a background job
> any more**, so every hazard below is now latent instead of live. That lowers
> the urgency and changes nothing about the analysis — the first background task
> to register re-arms all of it at once, with no warning and no failing test.

Citations into files that were, or later became, subject to concurrent edit are
given by **function or module-attribute name** rather than by line:
`explanation_handlers.ex`, `flow_finding_explanation.ex`, `ai/execution.ex`,
`ai/results.ex` and `ai/allowance.ex`. The last three earned that treatment the
hard way — the Slice-7.2a remediation moved them twice after this spec landed,
and every line cite into them had already drifted. Everything else — config,
workers, `Operations`, `Executor`, migrations — is cited by line and those cites
were re-verified at `d7459be3`.

## Objective

Make the durable AI execution queue survive node death and maintenance
contention without weakening the money guarantees of the execution kernel.

Two infrastructure gaps let an `ai_operations` row sit in a non-terminal
`execution_status` far longer than its polling consumers expect. Neither is an
accounting bug: allowance is never double-spent, and no second provider attempt
is ever bought. Both gaps only extend time-to-terminal — and both are invisible
to the current test suite, because `config/test.exs:48` sets `testing: :manual`,
which Oban normalizes into `plugins: []` and `queues: []`
(`deps/oban/lib/oban/config.ex:88-92`). No test today runs a producer or a
plugin.

## Current state

### The single Oban instance

The whole Oban configuration lives in one block, `config/config.exs:90-116`,
started from `lib/storyarn/application.ex:26`. **No environment overrides it.**
`config/runtime.exs`, `config/dev.exs` and `config/prod.exs` contain no `Oban`
key at all; `config/test.exs:48` is the only override and it only sets
`testing: :manual`.

| Setting                 | Value                                                        | Citation                          |
| ----------------------- | ------------------------------------------------------------ | --------------------------------- |
| `engine`                | `Oban.Engines.Basic`                                         | `config/config.exs:91`            |
| `:ai` queue concurrency | `2`                                                          | `config/config.exs:101`           |
| `plugins`               | `Pruner` (7-day `max_age`) and `Cron` — **and nothing else** | `config/config.exs:104-116`       |
| `*/15` AI crontab entry | `ExpireAIResultsWorker`                                      | `config/config.exs:112`           |
| `*/5` AI crontab entry  | `ReconcileAIReservationsWorker`                              | `config/config.exs:113`           |
| `shutdown_grace_period` | not set → Oban default `15_000` ms                           | `deps/oban/lib/oban/config.ex:45` |

`grep -rn "Lifeline"` over the repository (excluding `deps/` and `_build/`)
returns nothing.

### Three workers share the two `:ai` slots

| Worker                                           | Declaration                                          | Enqueued by                                 |
| ------------------------------------------------ | ---------------------------------------------------- | ------------------------------------------- |
| `Storyarn.Workers.AIExecutionWorker`             | `queue: :ai, max_attempts: 3`                        | `Execution.create_operation/2`              |
| `Storyarn.Workers.ReconcileAIReservationsWorker` | `queue: :ai, max_attempts: 1, unique: [period: 300]` | `Cron`, `*/5`                               |
| `Storyarn.Workers.ExpireAIResultsWorker`         | `queue: :ai, max_attempts: 3`                        | `Cron`, `*/15`, **plus its own follow-ups** |

Citations: `lib/storyarn/workers/ai_execution_worker.ex:3`,
`lib/storyarn/workers/reconcile_ai_reservations_worker.ex:3`,
`lib/storyarn/workers/expire_ai_results_worker.ex:3`.

**No registered task reaches the queue today** (was: exactly one, before 7.1a.0).
`ManagedDiagnostic` is `execution_mode: :inline`
(`lib/storyarn/ai/tasks/managed_diagnostic.ex:23`) and runs in the caller's
process (`Execution.maybe_run_inline/3`). The only background task was
~~`FlowFindingExplanation`~~ **[removed in 7.1a.0]**, `execution_mode: :background`
with `timeout_ms: 60_000` — the numbers this document is sized against, and the
shape any replacement will have. When it existed,
`Execution.create_operation/2` enqueues `AIExecutionWorker` **inside the same
transaction** that inserts the operation, its `ai_results` row and its allowance
reservation (`Execution.create_operation/2`, which enqueues `AIExecutionWorker`
inside the same `Repo.transaction`). The job therefore
becomes visible only if the money side committed.

The 60-second bound is enforced by the kernel, not by Oban: `Executor` runs the
provider call under `Elixir.Task.yield(async, task.timeout_ms)` and brutal-kills
it on expiry (`lib/storyarn/ai/executor.ex:58-67`). Oban's own `timeout/1`
callback is left at its `:infinity` default.

## The recovery chain this change must preserve

### Layer 1 — in-band, `AIExecutionWorker`

`max_attempts: 3`. Any attempt after the first calls
`Operations.recover_interrupted/1` **before** re-executing
(`lib/storyarn/workers/ai_execution_worker.ex:28-43`). The same recovery runs
after a failed, raised or thrown execution
(`ai_execution_worker.ex:45-63` — note the `rescue` and `catch` clauses at
`50-53`).

`Operations.recover_interrupted/1`
(`lib/storyarn/ai/operations.ex:220-237`) takes a `FOR UPDATE` lock and
dispatches on `recover_locked/1` (`operations.ex:272-296`):

| Locked row                                             | Transition                                                                                                                            | `error_classification`              | Returns  |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- | -------- |
| missing                                                | none                                                                                                                                  | —                                   | `:ok`    |
| `queued`                                               | none — the operation may still be executed                                                                                            | —                                   | `:ready` |
| `running`, `external_attempt_started_at` **nil**       | release allowance, delete result row, → `failed` (`operations.ex:275-285`)                                                            | `worker_interrupted_before_attempt` | `:ok`    |
| `running`, attempt started, usage row still `running`  | finish usage `unknown` + critical `unknown_operation` alert, release, delete result, → `unknown` (`operations.ex:298-300`, `467-494`) | `worker_interrupted`                | `:ok`    |
| `running`, attempt started, usage row already finished | release, delete result, → `unknown` (`operations.ex:302-310`) — **no alert on this branch**                                           | `worker_interrupted`                | `:ok`    |
| any terminal status                                    | none                                                                                                                                  | —                                   | `:ok`    |

`:ok` means "already terminal, stop"; the worker returns `:ok` and the job
completes. `:ready` means "still `queued`". On the final attempt `:ready` routes
to `Operations.fail_queued_after_retries/2` with `:worker_retries_exhausted`
(`ai_execution_worker.ex:56-58`), which releases the reservation, deletes the
result row and transitions `queued → failed` with
`error_classification = "worker_retries_exhausted"`
(`operations.ex:241-270`). On a non-final attempt `:ready` returns
`{:error, :ai_execution_interrupted}` and Oban schedules a retry.

**The load-bearing consequence:** the retry ladder only advances while the row
is still `queued`. Every `running` state — with or without a started attempt —
resolves _terminally_ inside `recover_interrupted/1`. A provider timeout is
likewise terminal: `Executor` maps it to `{:error, {:unknown, :timeout}}` and
`finalize/5` calls `Operations.finish_unknown/4`, after which
`Executor.run/1` returns `:ok`
(`lib/storyarn/ai/executor.ex:63-67`, `84-86`). **A 60-second provider timeout
never consumes an Oban attempt.** In practice attempts 2 and 3 are only ever
reached when `Operations.claim/1` itself could not commit — a database error or
lock failure — which is a sub-second failure.

There is no custom `backoff/1` on either worker, so Oban's default applies. In
`2.22.1` that default is _not_ the `attempt^4 + 15` formula from the
`Oban.Worker` docstring example (`deps/oban/lib/oban/worker.ex:180-182`); the
real implementation is `deps/oban/lib/oban/worker.ex:525-536`, which for
`max_attempts <= 20` computes
`Backoff.exponential(attempt, mult: 1, max_pow: 100, min_pad: 15)` followed by
`Backoff.jitter(mode: :inc)` — that is, `15 + 2^attempt` seconds plus up to 10%
increasing jitter (`deps/oban/lib/oban/backoff.ex:33-39`, `59-80`).

With `max_attempts: 3`:

| Attempt that failed | Base delay      | With `:inc` jitter |
| ------------------- | --------------- | ------------------ |
| 1                   | `15 + 2 = 17` s | 17–18 s            |
| 2                   | `15 + 4 = 19` s | 19–20 s            |

Total ladder ≈ **37–39 seconds** to reach `failed` /
`worker_retries_exhausted`, since the three attempts themselves are sub-second
in the only state that retries.

### Layer 2 — out-of-band, `ReconcileAIReservationsWorker`

Runs `*/5` (`config/config.exs:113`). Each run first calls
`Allowance.expire_due()` (`reconcile_ai_reservations_worker.ex:19`;
`Allowance.expire_due/0`), then selects stale operations
(`reconcile_ai_reservations_worker.ex:25-38`) with an **inner join**:

- `Operation` joined to `AllowanceReservation` on `reservation.operation_id == operation.id`;
- `reservation.status == "reserved"`;
- `reservation.inserted_at <= now - @default_stale_after_seconds` — `900`, overridable per-deployment via `Application.get_env(:storyarn, __MODULE__)[:stale_after_seconds]` (`reconcile_ai_reservations_worker.ex:15`, `57-61`);
- `operation.execution_status in ["queued", "running"]`.

For each row it records a **`critical`** `stale_reservation` operator alert
keyed `"stale-reservation:#{operation.id}"`, then dispatches by status
(`reconcile_ai_reservations_worker.ex:40-55`):

- `"queued"` → `Operations.fail_queued_after_retries(id, :stale_reservation)` → `failed`, `error_classification = "stale_reservation"`;
- `"running"` → `Operations.recover_interrupted(id)` → the table above.

The query is indexed on both sides:
`create index(:ai_allowance_reservations, [:status, :inserted_at])`
(`priv/repo/migrations/20260722220000_harden_ai_managed_invariants.exs:5`),
`create unique_index(:ai_allowance_reservations, [:operation_id])`
(`priv/repo/migrations/20260722210000_create_ai_managed_allowance.exs:77`) and
`create index(:ai_operations, [:execution_status, :inserted_at])`
(`priv/repo/migrations/20260722190000_create_ai_execution_kernel.exs:128`). No
index work is needed for this change.

### The resulting bound

The staleness clock starts at `reservation.inserted_at`, which is the same
transaction that inserted the operation (`Execution.create_operation/2`)
— effectively the moment the actor pressed the button. So:

> **900 s staleness + ≤ 300 s cron granularity ≈ ≤ 20 minutes** from request to
> a terminal `execution_status`, for any operation the reaper can see.

That bound is the contract this change must not regress. See **Finding 3** for
a way it can silently stretch to ≈ 25 minutes today.

### What layer 2 does not cover

The join to `AllowanceReservation` is an inner join, and a reservation exists
only for the managed lane. `Execution.create_operation/2` sets
`settlement_status = if route.lane == :managed, do: "reserved", else: "not_applicable"`
(`Execution.create_operation/2`) and `Execution.reserve!/2` only calls
`Settlement.reserve/1` for `%ExecutionRoute{lane: :managed}`, returning `:ok`
untouched for every other lane (`Execution.reserve!/2`).

Today this is harmless: the only registered task is managed-only
(`managed_diagnostic.ex:28`; the removed `FlowFindingExplanation` declared the
same `allowed_lanes: [:managed]` and `personal_byok_allowed?: false`), so every
operation that exists reserves and every operation is reachable by the reaper.

But the `:personal_byok` lane already exists end-to-end in
`Storyarn.AI.RouteResolver` (`route_resolver.ex:97`, `324`, `348`) and in
`ExecutionRoute` (`execution_route.ex:94`). **The moment a background task sets
`personal_byok_allowed?: true` — which is exactly what Slice 7.2b is for — its
operations insert no reservation, fall outside the reaper's inner join, and lose
layer 2 entirely.** With Finding 1 unaddressed they would have no recovery at
all beyond a clean in-process failure. Whoever enables a non-reserving
background lane must either widen this query to a union that does not depend on
`AllowanceReservation`, or add a second reaper keyed on
`operation.inserted_at` alone.

## Finding 1 — no `Oban.Plugins.Lifeline` anywhere

### What is wrong

The plugins list is `Pruner` + `Cron` and nothing else
(`config/config.exs:104-116`), and nothing overrides it. Oban's `Basic` engine
has no built-in rescue: `Lifeline` is the only mechanism that transitions
`oban_jobs` rows stuck in `executing` back to `available`
(`deps/oban/lib/oban/plugins/lifeline.ex:1-11`).

Consequence: when a node stops without letting `perform/1` return, its job row
stays `executing` **forever**. It is never re-fetched, so attempt 2 never
happens, so `Operations.recover_interrupted/1` is never called. **Recovery layer
1 cannot fire for that job at all.** The operation is rescued only by the `*/5`
cron reconciler, at the ≤ 20-minute bound instead of seconds.

### Why this is routine, not exotic

This is not limited to hardware failure or `kill -9`. Oban's watchman asks the
producer to stop, waits up to `shutdown_grace_period`, and if jobs are still
running it gives up, emitting `[:oban, :queue, :shutdown]` with an `:orphaned`
list (`deps/oban/lib/oban/queue/watchman.ex:32-57`). That grace period defaults
to **15 seconds** (`deps/oban/lib/oban/config.ex:45`) and is not configured
here.

The explanation task's provider timeout is **60 seconds**. Fifteen is less than
sixty. **Any ordinary deploy or restart that lands while an explanation is
mid-flight orphans its job row** and pushes that user's operation onto the
20-minute path. On Fly.io with manual deploys
(see `reference_branch_deploy_topology`) this is a normal-operation event, not
an incident.

### Proposed change

Add `Lifeline` to `config/config.exs:104` with an **explicitly sized**
`rescue_after`:

```elixir
plugins: [
  {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
  {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(3)},
  {Oban.Plugins.Cron, crontab: [...]}
]
```

The window is bounded on both sides and the default is useless here:

- **Lower bound**: `rescue_after` must exceed the longest legitimate attempt, or Lifeline will rescue jobs that are genuinely working. For `:ai` that is the 60 s task timeout plus the `finalize` transaction. Anything under ~90 s is unsafe.
- **Upper bound**: `rescue_after` must be well under the reaper's 900 s staleness window, or layer 1 still never wins. **Lifeline's default `rescue_after` is 60 minutes** (`deps/oban/lib/oban/plugins/lifeline.ex:37-38`) — three times the existing ≤ 20-minute bound, so adopting the default would change nothing observable. The value must be chosen, not inherited.
- 3–5 minutes satisfies both. The plugin sweeps once a minute by default (`:interval`, `60_000` ms).

### Trade-off

This is a **global** change to job handling, not an AI-local one. `Lifeline`
applies to every queue in the instance — `snapshots`, `project_restores`,
`imports`, `template_installs`, `localization`, `storage_cleanup`. Any of those
workers with a legitimate runtime longer than `rescue_after` becomes a
duplicate-execution candidate. Auditing the long-running workers (project
restore and template install in particular) is part of this change, not a
follow-up.

Oban states the hazard plainly: "This plugin may transition jobs that are
genuinely `executing` and cause duplicate execution"
(`deps/oban/lib/oban/plugins/lifeline.ex:15-16`). For the `:ai` queue
specifically, that hazard is **bounded but not zero**:

- It **cannot** buy a second provider call. `start_attempt_locked/3` rolls back with `:duplicate_external_attempt` if any `UsageEvent` already exists for the operation (`lib/storyarn/ai/operations.ex:93-99`), backed by `create unique_index(:ai_usage_events, [:operation_id])` (`priv/repo/migrations/20260722190000_create_ai_execution_kernel.exs:181`), and the attempt raises a `critical` `duplicate_attempt` alert (`operations.ex:54-57`, `446-465`). Allowance cannot be double-spent.
- It **can** destroy a good result. A rescued job re-enters at attempt > 1, calls `recover_interrupted/1`, sees `running` + a `running` usage row, and terminalizes the _still-live_ operation as `unknown` while the real attempt is in flight. When the genuine worker returns, `lock_running_attempt!/2` no longer matches and rolls back `:invalid_transition` (`operations.ex:385-396`), so a successful generation is discarded, the reservation is released, and a spurious `critical` `unknown_operation` alert is filed. Storyarn absorbs the provider cost — consistent with the documented invariant in `STORYARN_AI_OPERATIONS.md:92`, but the user sees a failure for work that succeeded.

That is precisely why `rescue_after` must sit above the 60 s attempt ceiling,
and why this finding needs its own verification pass rather than riding along
with Finding 2.

## Finding 2 — the reaper runs inside the queue it reaps

### What is wrong

`ReconcileAIReservationsWorker` is `queue: :ai, max_attempts: 1`
(`reconcile_ai_reservations_worker.ex:3`) and the `:ai` queue has concurrency
**2** (`config/config.exs:101`). Recovery layer 2 therefore depends on the same
producer as the work it is supposed to rescue.

**Total-stall case.** If the `:ai` queue is paused, mis-scaled to `0`, or its
producer never starts, then neither layer 1 (an `AIExecutionWorker` retry) nor
layer 2 (the reconciler) can run. An operation stays `"queued"` indefinitely,
its allowance stays reserved, and no alert is ever filed — the alert is written
_by_ the worker that cannot run. Nothing in the repo pauses a queue today
(`grep -rn "pause_queue\|scale_queue" lib/ test/` is empty), so this is a
latent operational trap rather than a live bug; note that `Cron` runs on the
leader independently of queue state, so reconciler jobs would still accumulate
as `available`, throttled to roughly one per 5 minutes by their own `unique`
window.

**Normal-operation case.** Even with a healthy producer, capacity is shared
three ways:

- Two concurrent explanations (each up to 60 s) delay the reconciler tick by up to a full attempt.
- The reconciler occupies 1 of the 2 slots whenever it runs, **halving execution capacity on every `*/5` tick**.
- `ExpireAIResultsWorker` is the sharper edge. It also sits on `:ai` (`expire_ai_results_worker.ex:3`), processes 100 rows per batch (`Results.@default_expiration_batch_size` and `Results.expire/2`), and **self-reschedules a follow-up with `schedule_in: 1` for as long as `more?` is true** (`expire_ai_results_worker.ex:54`, `74-78`). A backlog of _N_ expired results produces a chain of `ceil(N/100)` `:ai` jobs at one-second intervals, each holding a slot. It also declares `max_attempts: 3` with no `unique`, so retries and follow-ups can coexist.

The worst realistic case is not "the reconciler is a bit late": it is an expiry
backlog holding one slot continuously while a `*/15` tick — where the `*/5` and
`*/15` schedules align — puts the reconciler in the other, leaving **zero
capacity for user-facing execution**.

This was acknowledged, indirectly, in product code: the comment above
`@poll_deadline_ms` in ~~`…/handlers/explanation_handlers.ex`~~ **[removed in
7.1a.0]** recorded that "queue wait is unbounded by design (concurrency 2)". No
surviving code states it, which is precisely why it is written down here.

### Proposed change

Move both maintenance workers off the execution queue:

```elixir
queues: [
  # ...
  ai: 2,
  ai_maintenance: 1,
  storage_cleanup: 1
]
```

and change two declarations:

- `lib/storyarn/workers/reconcile_ai_reservations_worker.ex:3` → `queue: :ai_maintenance, max_attempts: 1, unique: [period: 300]`
- `lib/storyarn/workers/expire_ai_results_worker.ex:3` → `queue: :ai_maintenance, max_attempts: 3`

No crontab change is needed — `Cron` dispatches by worker module, and each
worker carries its own queue. `AIExecutionWorker` keeps `:ai` and its
concurrency of 2 untouched.

### Trade-off

This is the **local, safe** change, which is why it should land first and
separately from Finding 1. It touches three lines plus the queue list, changes
no job semantics, and makes layer 2 independent of the queue it reaps.

Costs to state explicitly:

- One more queue means one more producer and its polling overhead. Concurrency `1` is correct: both workers are serial sweeps and `ExpireAIResultsWorker`'s follow-up chain must not fan out.
- The reconciler stops being incidentally serialized against execution. It never relied on that — every transition it performs takes a `FOR UPDATE` lock on the operation row (`operations.ex:374`) — but the change does mean the reaper can now run _concurrently_ with an in-flight attempt on the same operation. That path is already exercised: it is the same interleaving the 900 s staleness window produces today whenever a long attempt outlives the cutoff.
- Rejected alternative: raising `ai: 2` to a higher concurrency. It does not fix the dependency (a producerless `:ai` queue still strands both layers), and it raises provider-call concurrency, which the beta cost ceilings deliberately bound (`STORYARN_AI_OPERATIONS.md:44-47`).

## Finding 3 (incidental, found while verifying) — the reconciler's own `unique` window can drop a tick

`ReconcileAIReservationsWorker` declares `unique: [period: 300]`
(`reconcile_ai_reservations_worker.ex:3`) and is scheduled `*/5` — exactly 300
seconds apart. Oban's uniqueness defaults are
`fields: [:args, :queue, :worker]`, `states: [:scheduled, :available, :executing, :retryable, :completed]`,
`timestamp: :inserted_at` (`deps/oban/lib/oban/job.ex:232-238`), and the window
predicate is `inserted_at >= now - period` — inclusive
(`deps/oban/lib/oban/engines/basic.ex:527-530`). The `Cron` plugin inserts via
`Oban.insert!/2` and merges only `meta`, which is not a unique field, so the
worker's own `unique` opts apply to every tick
(`deps/oban/lib/oban/plugins/cron.ex:285-321`).

Two ticks exactly 300 s apart therefore sit on the boundary: any tick jitter or
clock skew that makes the gap ≤ 300 s causes the insert to be silently deduped
against the previous **completed** job. When that happens the reconciler
effectively runs every 10 minutes, stretching the documented bound from
≈ 20 minutes to ≈ 25 minutes.

Recommended fix, as part of Finding 2's change: either drop `unique` (the
dedicated `ai_maintenance` queue with concurrency `1` already serializes it) or
shorten the window to something unambiguously below the schedule, e.g.
`unique: [period: 240]`. Do not widen it.

## Downstream consumer constraint

Any UI that polls an operation must size its own deadline against the _kernel's_
worst case, not against `timeout_ms`. Slice 7.2a's explanation panel learned
this the hard way, and ~~`StoryarnWeb.FlowLive.Handlers.ExplanationHandlers`~~
**[removed in 7.1a.0]** encoded the lesson as follows — **the next polling
surface must re-derive all of it, since there is no longer an implementation to
copy**:

- `@poll_interval_ms 1_000` and `@poll_deadline_ms 180_000` (the latter overridable per-deployment via a `:poll_deadline_ms` option);
- the deadline is measured from the first observed `"running"`, not from `execute` — `polling_since` is `nil` while queued and is stamped on the first `"running"` observation by `started_at/1`;
- while the operation is `"queued"` the panel polls with **no deadline at all**.

Two constraints follow for any future consumer:

1. **Do not size the deadline as `timeout_ms`.** The conservative envelope is `timeout_ms × max_attempts + summed backoff`. For this task that reads ~140–220 s, which is where the panel's 180 s comes from. As established under Layer 1, the true exposure is smaller — a provider timeout is terminal and never retries, so two 60 s attempts cannot occur in one job — but the conservative figure is the right one to design against: it is safe, and it is stable against future workers that _do_ retry mid-attempt.
2. **Queue wait is a separate, unbounded term.** With concurrency 2 shared three ways (Finding 2), `"queued"` can last minutes, and only layer 2 terminalizes it — at ≤ 20 minutes. A consumer that keeps polling `"queued"` indefinitely is making a deliberate bet on the reaper. If it instead imposes a queued-side deadline, that deadline must be ≥ the layer-2 bound, or the UI will report failure on operations that are still going to succeed.

Fixing Finding 2 shortens term 2 materially. It does not remove it, and this
document is not licence to shrink `@poll_deadline_ms`.

## Verification / Definition of Done

The `testing: :manual` mode in `config/test.exs:48` erases both queues and
plugins (`deps/oban/lib/oban/config.ex:88-92`), so none of this can be verified
by the existing suite shape. Each finding needs a test that starts a real Oban
instance, or drives the plugin's `handle_info/2` directly against seeded rows.

**Finding 2 (land first):**

- ExUnit: seed a `queued` operation with a stale reservation, run the reconciler via `Oban.drain_queue(queue: :ai_maintenance)`, assert `failed` / `"stale_reservation"` and one `critical` alert row.
- ExUnit: assert an `AIExecutionWorker` job and a reconciler job no longer share a queue — a regression guard on `Oban.Worker.__opts__/0` for both modules, so a later refactor cannot quietly move them back.
- ExUnit: assert `ExpireAIResultsWorker`'s follow-up (`schedule_in: 1`) is enqueued on `:ai_maintenance`, not `:ai`.
- Confirm the reconciler still reaches every managed operation: no query change, so the existing reconciliation tests must pass unmodified.

**Finding 1 (separate change, separate verification):**

- ExUnit: insert an `oban_jobs` row in `executing` with `attempted_at` older than `rescue_after`, run `Lifeline`, assert the row returns to `available` and that the subsequent attempt calls `Operations.recover_interrupted/1` and terminalizes as documented in the Layer 1 table.
- ExUnit: assert a job younger than `rescue_after` is **not** rescued. This is the test that protects against destroying good results.
- Audit every worker in `lib/storyarn/workers/` for a legitimate runtime above `rescue_after`, and document the finding for `RestoreProjectWorker`, `RecoverProjectWorker`, `ImportProjectWorker` and `InstallProjectTemplateWorker` specifically. If any can legitimately exceed it, they need their own `Oban.Worker.timeout/1` or an idempotency guard before `Lifeline` lands.
- Verify the duplicate-execution guard end-to-end: force a rescue against a live attempt and assert no second `ai_usage_events` row is created and that a `duplicate_attempt` alert is recorded.

**Both:**

- Confirm no config drift: `config/runtime.exs`, `config/dev.exs`, `config/prod.exs` still contain no `Oban` key, so `config/config.exs` remains the single source.
- `mix precommit` and `just quality` green.

## Non-goals

- Changing `:ai` concurrency, the 900 s staleness window, `timeout_ms`, or `max_attempts` on any worker. The recovery bound is a contract; this change makes it _reachable_, not tighter.
- Adding retries to provider calls. The kernel's zero-automatic-retry stance (`lib/storyarn/ai/executor.ex:2`, `lib/storyarn/workers/ai_execution_worker.ex:1`) is deliberate and unchanged.
- Introducing `Oban.Pro` / `DynamicLifeline`. Noted in the Oban docs as the accurate alternative (`deps/oban/lib/oban/plugins/lifeline.ex:13-17`); it is a paid dependency and out of scope.
- Broadcasting operation completion. The kernel emits no completion event, which is why the (now removed) panel polled at all; changing that is a separate product decision, and a live one now that no surface exists to constrain the design.
- Widening the layer-2 query for non-reserving lanes. Documented above under **What layer 2 does not cover** as a prerequisite for whoever enables a background `:personal_byok` task — it is not part of this change.
- Any alteration to allowance, settlement, or alert semantics.
