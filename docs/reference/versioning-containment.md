# Project snapshot lifecycle runbook

> Owner: Engineering
>
> Last reviewed: 2026-09-03
>
> Source of truth: `lib/storyarn/projects/versioning/commands/project_snapshot_lifecycle.ex`,
> `lib/storyarn/projects/versioning/adapters/storage/snapshot_archive_storage.ex`,
> `lib/storyarn/projects/versioning/execution/snapshot_archive_smoke.ex`,
> `lib/storyarn/projects/versioning/execution/project_snapshot_reconciliation.ex`,
> `lib/storyarn/projects/versioning/execution/project_snapshot_reconciliation_repair.ex`,
> `lib/storyarn/projects/assets/adapters/storage/`, `lib/storyarn/release.ex`, and
> `lib/storyarn/workers/`, plus
> `priv/repo/migrations/20260811180000_make_project_snapshots_v2_only.exs`,
> `priv/repo/migrations/20260812100000_remove_transitional_snapshot_cutover_scaffolding.exs`, and
> `priv/repo/migrations/20260820160000_add_abandoned_import_snapshot_cleanup_reason.exs`

Project snapshots have one canonical representation: a v2 full ZIP archive and
its manifest sidecar. There is no runtime switch, alternate format, linked mode,
conversion path, or compatibility reader.

The operational evidence for this contract is recorded separately in
[ENG-52 operational recovery validation](eng-52-operational-recovery-validation.md).
That record distinguishes a point-in-time provider observation from a completed
recovery drill.

## Ownership and escalation

Engineering owns this runbook, the recovery drill, and the decision to resume
writers. The engineer starting an incident or drill remains the operational
owner until an explicit handoff is recorded in the incident or ENG-52 evidence.

Escalate immediately to the Engineering owner as a highest-severity production
incident when production snapshot integrity is unknown, a production recovery
cannot be completed, or production database and object-store state cannot be
reconciled. Escalate provider
permission, inventory, or durability failures through the approved Fly/Tigris
account owner; escalate database restore or PITR failures through the approved
Neon account owner. If output contains a credential, signed URL, imported
content, or personal data, stop collecting and sharing it, treat the exposure as
a security incident, and do not attach the raw output to GitHub or Linear.

## Canonical lifecycle

- A request persists the snapshot identity, a minimal capacity lease, and one
  `snapshot_archives` job. It does not serialize project content or assemble ZIP
  bytes in the web process.
- The worker captures a repeatable-read project view, persists the immutable
  build input, calculates the exact archive accounting, and extends the storage
  reservation before provider I/O starts.
- Every build owns `snapshot.zip` and `manifest.json` under paired namespaces:

  ```text
  projects/{project_id}/snapshots/archives/v2/staging/{token}/
  projects/{project_id}/snapshots/archives/v2/ready/{token}/
  ```

- The ZIP contains `manifest.json`, `project.json`, and the deduplicated `blobs/`
  inventory. Publication verifies and copies the archive before publishing the
  byte-identical manifest sidecar last.
- Ready storage accounting is exactly the archive plus sidecar bytes. The
  transient database capture is deleted when the ready transition commits.
- Lifecycle transitions are forward-only and generation-fenced in Ecto and
  PostgreSQL. A stale build, cancellation, retry, finalizer, or cleanup delivery
  cannot mutate a newer generation.
- Before a snapshot or parent is deleted, Storyarn records the exact four-key
  staging/ready inventory in a durable cleanup receipt and
  `snapshot_cleanup_intents` row. Quota release requires durable cleanup
  ownership unless the reservation proves storage never started.

Snapshot build capacity uses a short renewable lease. The worker records an
immediate generation-fenced heartbeat after claiming its Oban job and renews it
while alive. Expiry alone is never deletion authority: maintenance also requires
the exact job to be terminal or absent and quiescent.

Cleanup is bounded, checkpointed, generation-fenced, and duplicate-safe.
Provider or namespace failures preserve the remaining inventory for replay.
Invalid inventory or ownership fails closed for manual repair. Cleanup performs
two delete-and-verify passes separated by the PostgreSQL-enforced quiescence
window so a delayed writer cannot escape the second pass.

## Download contract

A download request reauthorizes the current user for the exact project and
snapshot, acquires the deletion fence, and signs a short-lived private provider
GET for the persisted ZIP. Production application nodes do not rebuild or proxy
ZIP bytes. Local development uses the same authorized endpoint with private
ranged delivery.

The durable zero-byte download lease remains active for the signed-URL start
window, the supported transfer window, and a safety margin. Repeated grants for
one snapshot coalesce onto the latest generation-fenced lease, so one request
cannot release another request's protection.

Production may override the grant start window with
`PROJECT_SNAPSHOT_DOWNLOAD_SIGNED_URL_TTL_SECONDS` (1–300 seconds) and the
supported transfer window with
`PROJECT_SNAPSHOT_DOWNLOAD_MAX_TRANSFER_SECONDS`. Boot rejects non-positive
values and refuses a signed-grant TTL above the private storage facade's
five-minute limit. The deletion lease is derived from both values and cannot be
configured shorter than the download contract.

## Ready archive trust boundary

The worker byte-counts and SHA-256 verifies the archive before the row becomes
`ready`. Publication uses a random generation namespace and create-if-absent
provider operations; Storyarn never rewrites a published ready key.

A normal download deliberately does not re-hash the complete archive in the web
request. `verified` means the bytes passed publication-time verification. A
provider-side overwrite performed outside Storyarn can remain downloadable
until reconciliation detects it and an explicit repair changes the snapshot
state.

Preservation of ready-key bytes is therefore part of the private object-store
trust boundary. The real-provider smoke proves one archive at one point in
time; it does not prove WORM semantics. Supporting hostile same-key replacement
without proxying every download would require persisted provider object-version
identities and version-specific signed GETs.

## Observation-only reconciliation

Snapshot reconciliation is an operator-started dry run. It verifies every ready
archive that existed at the run's database high-watermark against its immutable
row, archive and sidecar digests, publication claim, committed reservation, and
exact two-object ready namespace. It then performs a resumable provider scan
under `projects/` and records:

- missing or corrupt ready objects;
- database, inventory, or accounting mismatches;
- quiescent expired build reservations;
- terminal cleanup intents;
- malformed reserved-root keys;
- unowned canonical namespaces; and
- abandoned temporary namespaces.

The run never updates integrity, settles reservations, retries cleanup, deletes
or copies objects, or changes quota. A finding is a repair candidate, not
mutation authority.

Start and inspect a run on a release node:

```text
/app/bin/storyarn rpc 'Storyarn.Platform.Release.start_project_snapshot_reconciliation()'
/app/bin/storyarn rpc 'Storyarn.Platform.Release.inspect_project_snapshot_reconciliation(123, 0, 100)'
```

Only one run may be active for a physical provider namespace. Work uses the
`snapshots_maintenance` queue. Continuations are generation-fenced and their
cursor, monotonic counters, and deduplicated findings commit together. Object,
byte, finding, page, cursor, namespace, and provider limits fail closed.

The global provider scan cannot enumerate every incomplete multipart upload, so
completed runs retain `multipart_inventory_state = unsupported` and
`physical_inventory_complete = false`. Never interpret completion as proof that
multipart drift is zero.

For each durably owned archive or sidecar key, cleanup has a narrower exact-key
guarantee: it lists and aborts incomplete multipart uploads until a bounded
verification pass proves the inventory empty. A later empty pass after the full
quiescence window is required before the cleanup receipt can be consumed. List,
pagination, part, abort, delete, or quiescence failures leave cleanup pending.

### Global multipart inventory after PITR or uncertain ownership

Global multipart inventory is observation only. It never grants deletion
authority. There is deliberately no global abort operation: an upload may
belong to a live writer, and a database recovered through PITR may not contain
the ownership row for a later provider upload.

After a PITR exercise, or whenever database/object ownership is uncertain:

1. Contain new writers and pause the affected queues using the procedure below.
2. Keep the recovered database isolated from production traffic and preserve
   the provider namespace unchanged.
3. Run observation-only snapshot reconciliation against the isolated candidate.
4. Obtain a provider-level, read-only multipart inventory through approved
   operational tooling. Do not print storage keys, upload IDs, bucket names, or
   request URLs into shared evidence.
5. Match every candidate to a durable cleanup receipt and exact key in the
   recovered database. Use only the owning application cleanup path when that
   match is proven.
6. Leave unmatched uploads untouched, record only aggregate sanitized counts,
   and escalate for manual investigation.

Run the public, read-only application path for step 4 on a release node:

```bash
/app/bin/storyarn rpc 'IO.inspect(Storyarn.Projects.inspect_storage_multipart_inventory(), label: "Multipart inventory status")'
```

The command is the shared, aggregate detection control. It emits only the
metrics documented below and returns `:ok` or a bounded failure classification
such as `:inventory_limit_exceeded`, `:unsupported`, `:invalid_response`, or
`:provider_error`. It does
not print provider keys, upload IDs, bucket names, filenames, or raw provider
errors. Candidate identification for the matching step still requires approved,
access-controlled provider tooling; that detailed output must never be copied
into the command, metrics, logs, GitHub, or Linear. Until the aggregate metrics
reach the production reporter and their alert is exercised, ENG-52 remains open
and no operator may claim complete physical coverage.

## Fenced reconciliation repair

Repair consumes immutable findings from a completed inspection but treats their
evidence as stale until it is revalidated. Integrity actions hash the exact
provider object before taking workspace and snapshot locks. Cleanup actions lock
the intent and revalidate the exact inventory, ownership receipt, and provider
namespace. A changed or already-resolved subject is a successful no-op.

| Finding                                                         | Automated action                                                    | Manual boundary                                                   |
| --------------------------------------------------------------- | ------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Missing ready archive or sidecar                                | Mark missing after exact generation and absence are revalidated     | Identity, ownership, lifecycle, or provider result changed        |
| Corrupt ready archive or sidecar                                | Mark corrupt after exact size and digest failure are reproduced     | Replacement appeared or corruption cannot be reproduced           |
| Stale build reservation                                         | Cleanup only the same expired, quiescent build without a live owner | Job, claim, generation, namespace, or cleanup proof is ambiguous  |
| Terminal cleanup failure                                        | Replay only an exact, still-terminal, provider-replayable intent    | Inventory, ownership, namespace, or integrity evidence is invalid |
| Abandoned or ambiguous provider object                          | Report only                                                         | Automatic deletion lacks a durable conditional-delete identity    |
| Database, inventory, accounting, or verification-limit mismatch | Report only                                                         | Automatic reconstruction is not proven safe                       |

Plan and inspect repairs in bounded pages:

```text
/app/bin/storyarn rpc 'Storyarn.Platform.Release.repair_project_snapshot_reconciliation(123, 0, 50)'
/app/bin/storyarn rpc 'Storyarn.Platform.Release.inspect_project_snapshot_reconciliation_repairs(123, 0, 100)'
```

The planning command persists each action and immediately enqueues its
asynchronous delivery. Wait for every action to reach a terminal outcome, then
start a new reconciliation run. Never reuse the repaired run as readiness
evidence. Manual and failed outcomes require operator review.

## V2-only schema cutover

Migration `20260811180000_make_project_snapshots_v2_only.exs` is irreversible
and fails closed before changing the schema if any live retired ownership still
exists. The cutover checks are frozen in the historical migrations rather than
implemented by live release-task code. When the first destructive migration,
`20260804120000`, is still pending, it requires `project_snapshots` to be empty,
rejects active pre-cutover snapshot workers, and conditionally requires legacy
`entity_versions` to be empty. Migration `20260811180000` later requires all of
the following retired ownership to be absent:

- legacy `entity_versions` while the storage-accounting reset migration
  `20260804120000` is still pending; versions created after that migration are
  preserved;
- v1 publication claims;
- linked-conversion or v1-owned storage reservations;
- linked or v1 cleanup intents;
- live cleanup requests containing v1 or linked-conversion keys;
- active `BuildProjectSnapshotWorker` jobs in any queue; or
- active generic cleanup jobs carrying retired snapshot keys.

The first destructive migration installs persistent database barriers in its
own transaction. The lifecycle-hardening and barrier-checkpoint migrations
verify those barriers before their DDL; the final v2-only migration instead
locks every affected table and revalidates the complete ownership precondition
before replacing the barriers with the canonical constraints. The barriers
reject every project-snapshot insert, the listed live pre-cutover snapshot
workers, and—until the storage-accounting reset commits—new `entity_versions`.
Each migration has its own transaction, so the barriers intentionally remain
installed if an intermediate migration fails. Normal recovery is to fix the
migration failure and rerun the release migrator:

```text
/app/bin/migrate
```

Do not manually remove the barriers merely to retry or abandon the cutover.
When Fly's release command fails, the active application machines still run the
previous image. More importantly, an intermediate migration may already have
committed schema that the previous binary cannot safely write. Recovery is
therefore forward-only: leave the barriers installed, fix the failing migration
or its precondition, and deploy the corrected image so `/app/bin/migrate` can
resume. Pause the snapshot and storage-cleanup queues while investigating.
There is no supported production bypass that removes the barriers from a
partially migrated schema.

The current production assumption is that the project-snapshot ownership sets
are empty because no project snapshots have been created. The conditional
`entity_versions` precondition is independent: it applies only when migration
`20260804120000` is still pending. If it fails, inspect and back up the legacy
versions, then retire their rows and referenced provider objects together under
the pre-cutover procedure before retrying. Never delete only the database rows
and leave their storage keys orphaned. If the migration reports an active
snapshot build, let the pre-cutover deployment finish or settle it before
retrying. For other retired snapshot ownership, use that binary's durable
cleanup protocol to purge the owned provider bytes. Terminal immutable cleanup
receipts and namespace evidence remain preserved for audit, but the replacement
database trigger can never create new retired-format evidence.

Migration
`20260812100000_remove_transitional_snapshot_cutover_scaffolding.exs` is the
required second deployment after the v2-only release. Before destructive DDL,
it locks snapshots, publication claims, reservations, cleanup intents, and Oban
jobs. It proves that the v2-only marker, all canonical v2 `CHECK` constraints,
and the three transitional constraints have their exact validated definitions;
both retired columns contain only `NULL`; and no active retired or misrouted
snapshot worker remains. It then removes the two retained compatibility columns
and the transitional worker-name routing fence.

Each table-lock acquisition has a transaction-local five-second
`lock_timeout`. This bounds contention on the continuously active `oban_jobs`
table without changing the database or role default. PostgreSQL acquires the
listed locks one at a time, so the timeout applies separately to each lock
attempt rather than to the migration as a whole. If lock acquisition times out,
the migration transaction rolls back and retains all transitional scaffolding.
Do not remove or increase the timeout while application traffic is active;
identify the blocking transaction, let it finish or stop it through the normal
operational procedure, and retry the release command during a quiet window.

Run this migration only after the preceding v2-only deployment has completed
and every application, worker, release-command, and one-off machine runs that
code. The database preflight cannot prove which application image an external
machine has loaded. This includes stopped Fly Machines that may auto-start.
Before deploying this cleanup release, inventory the complete application fleet
and remove or update every machine that can still start a pre-v2 image.

For an existing production database, `/app/bin/migrate` requires a one-release
operator acknowledgement in addition to its database checks. Stage the exact
migration version before starting the normal deploy:

```text
fly secrets set --stage -a storyarn-prod \
  PROJECT_SNAPSHOT_SCAFFOLDING_CLEANUP_AUTHORIZATION=20260812100000
```

The value is neither a runtime feature flag nor an override for a failed
precondition. It only records that the external machine inventory was checked;
a missing v2-only marker, weakened constraint, non-`NULL` retired value, or
active retired/misrouted job still aborts before destructive DDL. A genuinely
empty database may bootstrap from zero without this acknowledgement, and once
the cleanup marker exists later releases no longer require it. If that empty
bootstrap fails before reaching the v2-only marker, the next production run
fails closed because the schema is no longer provably fresh. Recreate the still
empty database and retry from zero; do not use the cleanup acknowledgement to
bypass the required release boundary. If the failed bootstrap has acquired any
real data, treat it as an existing deployment and advance it through the
preceding v2-only release first.

After the deploy and release command succeed, remove the temporary value:

```text
fly secrets unset -a storyarn-prod \
  PROJECT_SNAPSHOT_SCAFFOLDING_CLEANUP_AUTHORIZATION
```

If the release command fails, keep the acknowledgement staged, fix the
precondition or migration, and redeploy forward. Once the cleanup commits, the
schema is deliberately incompatible with pre-v2 binaries and rollback to one
is unsupported. Leave the canonical v2 constraints intact; do not reconstruct
the retired columns or worker-name fence.

## Real Tigris validation

CI and local-adapter tests do not prove the production bucket, credentials,
signed URLs, response headers, multipart permissions, or lifecycle policy.
Before the first real project snapshot, perform one controlled validation using
the deployed application and private Tigris configuration.

1. Verify the application principal can perform the snapshot object operations
   and has the provider equivalents of:

   - `s3:ListBucketMultipartUploads`;
   - `s3:ListMultipartUploadParts`; and
   - `s3:AbortMultipartUpload`.

2. Evaluate whether the provider supports a native bounded abort rule for
   incomplete multipart uploads. On 2026-09-02 the real Tigris endpoint rejected
   `AbortIncompleteMultipartUpload` with HTTP 400 and `InvalidRequest`; it
   reported support only for completed-object expiration rules. Do not
   substitute a global object-expiration rule: it does not clean incomplete
   uploads and can delete valid completed objects.
3. Create one small full snapshot with the deployed background worker and wait
   until it is `ready` and `verified`.
4. Run the read-only smoke on the release node:

   ```bash
   /app/bin/storyarn rpc 'Storyarn.Projects.run_snapshot_archive_smoke!(SNAPSHOT_ID)'
   ```

The selected archive must be at most 300 MiB. The smoke proves exact-key
multipart inventory access, streams the full signed GET through incremental
SHA-256 and byte-count checks, and verifies a signed Range GET plus the expected
private response headers. It never prints the bearer URL or uploads, overwrites,
aborts, or deletes provider data.

Because the smoke is read-only, it cannot prove part listing or abort permission
without intentionally creating an incomplete upload. Verify those permissions
from the actual provider policy or a separately controlled multipart probe. A
passing unit test or syntactically valid signed URL is not a substitute for the
real-provider check.

There is no archive-write feature flag or user rollout gate. With the current
controlled production usage, deploy the canonical code during a short window in
which no project snapshots are being requested, run this validation once, and
forward-fix any failure before creating another snapshot.

## Operational containment

Entity-version restore remains independently contained. Keep these runtime
values disabled until their own contracts are released:

```text
SHEET_VERSION_RESTORE_ENABLED=false
FLOW_VERSION_RESTORE_ENABLED=false
SCENE_VERSION_RESTORE_ENABLED=false
ENTITY_TRASH_RETENTION_ENABLED=false
```

These switches do not affect project snapshot creation or downloads.

### Recovery telemetry and minimum alert contract

`METRICS_ENABLED=true` starts the Prometheus reporter and its dedicated listener
synchronously before the database pollers, so their first observations are
retained. The listener binds to `0.0.0.0:9091`, accepts only `GET /metrics`, and
is declared through Fly's `[metrics]` configuration. It is not an application
route and port `9091` must never be added to the public HTTP service. This
matches Fly's [custom-metrics contract](https://fly.io/docs/monitoring/metrics/#custom-metrics).
Metric labels are limited to fixed queue names and bounded outcome
classifications; job arguments, entity identifiers, storage keys, filenames,
imported content, provider errors, and exception messages are excluded.

The minimum dashboard has five views:

1. backlog, due work, executing work, oldest waiting and executing age, maximum
   recorded error count, configured capacity, effective capacity, pause state,
   and runtime availability for all eight operational recovery and inventory
   queues;
2. job outcomes and exceptions by queue, correlated with the domain terminal
   outcomes below rather than inferred from delivery timing alone;
3. ordinary storage-compensation and snapshot-lifecycle cleanup backlog,
   terminal failures, oldest age, and observation freshness;
4. global multipart count, oldest age, observation freshness, scan completeness,
   and scan failures for the complete configured provider namespace; and
5. snapshot-import terminal outcomes plus reconciliation's missing, corrupt,
   orphan, stale-reservation, and terminal-cleanup summaries, including both
   projector freshness and the age of the latest completed run.

The metrics poller reloads the latest immutable completed reconciliation for
the currently configured provider namespace and its aggregate finding summary
from PostgreSQL every 15 minutes. This rehydrates
the gauges after a deployment or process restart without exporting run,
snapshot, project, workspace, cleanup, or storage identifiers. The
`observed_at` metric proves that this projection is still polling successfully;
`latest_completed_at` records when the underlying reconciliation itself
finished. They are deliberately separate: repeatedly projecting an old run
must not make its integrity observation look current. For the current no-user
environment, complete at least one observation-only reconciliation every 24
hours; review that cadence before admitting traffic.

The scheduled provider-wide multipart inspection is guarded by the same
`METRICS_ENABLED` opt-in. With observability disabled the cron job performs no
provider request; operators can still invoke the read-only Projects entrypoint
manually for an explicit drill. This prevents an unobserved scan from creating
provider load or retry traffic.

The Yarn execution, Yarn-expiration, snapshot-import delivery, reconciliation,
and reconciliation-repair counters below are best-effort edge signals. Their
corresponding domain state can be committed before the telemetry event is
emitted, so a process crash in that narrow interval can lose the counter without
losing the durable terminal record. Treat the import and reconciliation tables
as the source of truth. The completed-reconciliation projection rehydrates
integrity findings, but it does not project failed runs or failed/manual repair
actions. These counters are useful supplemental alerts, but they are not
evidence that every terminal transition is observed. Before ENG-52 can claim
complete terminal coverage, add and deploy either a durable polling projection
over all of those records or a persisted outbox, and prove its restart behavior.

Use the exported metric names below as the minimum alert definitions. Thresholds
are deliberately conservative for the current no-user environment and must be
reviewed before traffic is admitted:

```promql
# Reporter or database poll absent/stale. The poll interval is 15 minutes.
absent(storyarn_oban_queue_poll_stop_success)
max(storyarn_oban_queue_poll_stop_success) == 0
absent(storyarn_oban_queue_poll_stop_last_success_unix_seconds)
time() - max(storyarn_oban_queue_poll_stop_last_success_unix_seconds) > 1200
sum(increase(storyarn_oban_queue_poll_stop_failure_count[30m])) > 0
or sum(
  storyarn_oban_queue_poll_stop_failure_count
    unless storyarn_oban_queue_poll_stop_failure_count offset 30m
) > 0

# A recovery queue is unavailable, unexpectedly paused, or has due work older
# than 20 minutes. Suppress the pause alert only inside a recorded containment.
min by (queue) (storyarn_oban_queue_snapshot_runtime_available) < 1
count(count by (queue) (storyarn_oban_queue_snapshot_runtime_available)) != 8
max by (queue) (storyarn_oban_queue_snapshot_paused) > 0
max by (queue) (storyarn_oban_queue_snapshot_due_count) > 0
  and max by (queue) (storyarn_oban_queue_snapshot_oldest_due_age_seconds) > 1200
max by (queue) (storyarn_oban_queue_snapshot_executing_count) > 0
  and max by (queue) (storyarn_oban_queue_snapshot_oldest_executing_age_seconds) > 900
max by (queue) (storyarn_oban_queue_snapshot_retryable_count) > 0
  and max by (queue) (storyarn_oban_queue_snapshot_max_recorded_error_count) >= 3

# Worker exceptions, plus discards only in the three critical snapshot-delivery
# queues. Yarn and maintenance-domain failures have dedicated alerts below.
sum by (queue) (increase(storyarn_oban_job_exception_count[15m])) > 0
or sum by (queue) (
  storyarn_oban_job_exception_count
    unless storyarn_oban_job_exception_count offset 15m
) > 0
sum by (queue) (
  increase(
    storyarn_oban_job_stop_count{
      queue=~"snapshot_archives|snapshot_restores|snapshot_imports",
      state="discard"
    }[15m]
  )
) > 0
or sum by (queue) (
  storyarn_oban_job_stop_count{
    queue=~"snapshot_archives|snapshot_restores|snapshot_imports",
    state="discard"
  }
  unless storyarn_oban_job_stop_count{
    queue=~"snapshot_archives|snapshot_restores|snapshot_imports",
    state="discard"
  } offset 15m
) > 0

# Best-effort edge signal: a Yarn execution reached a failed or expired
# terminal domain outcome. Do not infer this only from the Oban job result:
# delivery can still succeed. Its durable polling/outbox counterpart remains
# required for complete coverage.
sum(increase(storyarn_import_execute_stop_count{format="yarn",status=~"failed|expired"}[15m])) > 0
or sum(
  storyarn_import_execute_stop_count{format="yarn",status=~"failed|expired"}
    unless storyarn_import_execute_stop_count{format="yarn",status=~"failed|expired"} offset 15m
) > 0

# Best-effort edge signal: the maintenance reconciler can terminalize an
# accepted Yarn attempt whose delivery job vanished or exceeded the absolute
# deadline. Preview expiry is expected and is deliberately excluded. Its
# durable polling/outbox counterpart remains required for complete coverage.
sum(increase(storyarn_import_expiration_terminal_count{format="yarn",disposition="accepted"}[15m])) > 0
or sum(
  storyarn_import_expiration_terminal_count{format="yarn",disposition="accepted"}
    unless storyarn_import_expiration_terminal_count{format="yarn",disposition="accepted"} offset 15m
) > 0

# Best-effort edge signal: a snapshot ZIP import reached its durable failed
# state, or its worker boundary rejected an exception/invalid contract, even if
# delivery itself was ACKed. Its durable polling/outbox counterpart remains
# required for complete coverage.
sum(increase(storyarn_snapshot_import_delivery_stop_count{outcome=~"terminal_failure|unexpected"}[15m])) > 0
or sum(
  storyarn_snapshot_import_delivery_stop_count{outcome=~"terminal_failure|unexpected"}
    unless storyarn_snapshot_import_delivery_stop_count{outcome=~"terminal_failure|unexpected"} offset 15m
) > 0

# Durable cleanup cannot converge within one maintenance interval plus margin.
absent(storyarn_assets_storage_compensation_backlog_observed_at_unix_seconds)
time() - storyarn_assets_storage_compensation_backlog_observed_at_unix_seconds > 1200
storyarn_assets_storage_compensation_backlog_due_count > 0
  and storyarn_assets_storage_compensation_backlog_oldest_due_age_seconds > 1200
absent(storyarn_snapshot_cleanup_backlog_observed_at_unix_seconds)
time() - storyarn_snapshot_cleanup_backlog_observed_at_unix_seconds > 1200
max(storyarn_snapshot_cleanup_backlog_terminal_failures) > 0
max(storyarn_snapshot_cleanup_backlog_repeated_terminal_failures) > 0

# The read-only global multipart scan is missing, stale, incomplete, failing, or
# observes an upload older than 30 minutes. Count alone is not deletion
# authority. The scheduled scan interval is 30 minutes.
absent(storyarn_storage_multipart_inventory_snapshot_observed_at_unix_seconds)
time() - storyarn_storage_multipart_inventory_snapshot_observed_at_unix_seconds > 2700
storyarn_storage_multipart_inventory_snapshot_inventory_complete < 1
sum(increase(storyarn_storage_multipart_inventory_snapshot_failure_count[45m])) > 0
or sum(
  storyarn_storage_multipart_inventory_snapshot_failure_count
    unless storyarn_storage_multipart_inventory_snapshot_failure_count offset 45m
) > 0
storyarn_storage_multipart_inventory_snapshot_oldest_age_seconds > 1800

# Best-effort edge signals: reconciliation or repair reached a failed/manual
# domain outcome. Their durable failed-run/action projection or outbox remains
# required for complete coverage. The later completed-run gauges are durable.
sum(increase(storyarn_snapshot_reconciliation_stop_count{status="failed"}[15m])) > 0
or sum(
  storyarn_snapshot_reconciliation_stop_count{status="failed"}
    unless storyarn_snapshot_reconciliation_stop_count{status="failed"} offset 15m
) > 0
sum(increase(storyarn_snapshot_reconciliation_repair_stop_count{outcome=~"failed|manual"}[15m])) > 0
or sum(
  storyarn_snapshot_reconciliation_repair_stop_count{outcome=~"failed|manual"}
    unless storyarn_snapshot_reconciliation_repair_stop_count{outcome=~"failed|manual"} offset 15m
) > 0
sum(increase(storyarn_snapshot_reconciliation_repair_recovery_stop_failure_count[15m])) > 0
or sum(
  storyarn_snapshot_reconciliation_repair_recovery_stop_failure_count
    unless storyarn_snapshot_reconciliation_repair_recovery_stop_failure_count offset 15m
) > 0
# The persisted reconciliation projection must remain live, must have a
# completed source run, and that source observation must be no older than 24h.
absent(storyarn_snapshot_reconciliation_projection_stop_success)
min(storyarn_snapshot_reconciliation_projection_stop_success) < 1
absent(storyarn_snapshot_reconciliation_projection_stop_observed_at_unix_seconds)
time() - min(storyarn_snapshot_reconciliation_projection_stop_observed_at_unix_seconds) > 1200
sum(increase(storyarn_snapshot_reconciliation_projection_stop_failure_count[30m])) > 0
or sum(
  storyarn_snapshot_reconciliation_projection_stop_failure_count
    unless storyarn_snapshot_reconciliation_projection_stop_failure_count offset 30m
) > 0
absent(storyarn_snapshot_reconciliation_projection_stop_latest_completed_available)
min(storyarn_snapshot_reconciliation_projection_stop_latest_completed_available) < 1
absent(storyarn_snapshot_reconciliation_projection_stop_latest_completed_at_unix_seconds)
time() - min(storyarn_snapshot_reconciliation_projection_stop_latest_completed_at_unix_seconds) > 86400
max(storyarn_snapshot_reconciliation_projection_stop_finding_count) > 0
max(storyarn_snapshot_reconciliation_projection_stop_missing_ready_snapshot_count) > 0
max(storyarn_snapshot_reconciliation_projection_stop_corrupt_ready_snapshot_count) > 0
max(storyarn_snapshot_reconciliation_projection_stop_terminal_cleanup_failure_count) > 0
```

Counter alerts combine `increase` with `unless ... offset`: bounded label series
do not exist before their first event, so the second branch catches a first
failure that arrived before Prometheus had a zero-valued sample. Gauges describe
the latest emitted observation. Reconciliation alert gauges are rehydrated from
the latest durable completed run; their separate projection and source-run
timestamps prevent a restart or repeated projection from hiding missing or
stale integrity evidence.
The critical-queue discard rule is a request for triage, not proof of data loss.
Correlate it with the durable snapshot/import state and the domain alerts above.
Expected authorization fences, stale maintenance work, and invalid maintenance
payloads can legitimately discard delivery jobs, which is why there is no
all-queue discard alert. Keep triage aggregate and sanitized: do not copy job
arguments, object keys, imported content, identifiers, or raw provider errors
into the incident record.

The exporter registry is in memory and starts empty after every process restart.
Installed alert rules must therefore include a startup grace with `for`: at
least 30 minutes for database-backed cleanup gauges and at least 45 minutes for
the 30-minute provider inventory. The Oban and reconciliation pollers emit on
startup, so five minutes is sufficient for their missing-series alerts. Keep
the due-work alert based on `due_count` and `oldest_due_age_seconds`:
`oldest_waiting_age_seconds` deliberately includes future scheduled/backoff
work for dashboard context and must not page by itself.

An alert is not operational merely because this query exists in the runbook.
ENG-52 requires the deployed reporter to be scraped by a real backend, every
rule to be installed with an owned receiver, and one sanitized firing and
recovery test to be linked from the evidence record. A Fly dashboard without a
working notification receiver does not satisfy that criterion. At the time of
this document, the dashboard, receiver, installed rules, and firing/recovery
evidence are still pending; none of the PromQL above is claimed as deployed.
Port `9091` must remain private and must not be published as a Fly service.

### Queue containment

Use the smallest queue set that contains the incident. For a Yarn replacement
incident, pause `imports` first; keep `imports_maintenance` and
`storage_cleanup` running unless their own behaviour is under investigation so
expired attempts and exact-key cleanup can converge. For a database restore,
provider-namespace ownership incident, or full ENG-52 recovery drill, contain
all seven recovery queues:

```text
imports
imports_maintenance
snapshot_archives
snapshot_restores
snapshot_imports
snapshots_maintenance
storage_cleanup
```

Run the following on a release node. It prints only queue names, pause state,
limits, and aggregate running counts; it does not print job IDs or arguments:

```bash
/app/bin/storyarn rpc '
queues = [:imports, :imports_maintenance, :snapshot_archives, :snapshot_restores,
  :snapshot_imports, :snapshots_maintenance, :storage_cleanup]
Enum.each(queues, fn queue -> :ok = Oban.pause_queue(queue: queue) end)
states = Enum.map(queues, fn queue ->
  case Oban.check_queue(queue: queue) do
    nil -> %{queue: queue, paused: :not_running, limit: 0, running_count: 0}
    state -> %{queue: queue, paused: state.paused, limit: state.limit,
      running_count: length(state.running)}
  end
end)
IO.inspect(states, label: "Recovery queue containment")
'
```

Pausing prevents new jobs from starting; already-running jobs continue. Do not
begin PITR comparison or mutate provider data until every affected
`running_count` is zero. The pause signal is not application admission control
and is not durable across a machine restart. In the current no-user production,
perform containment inside a controlled window with no requests. Before real
traffic exists, define a separate ingress or application admission control;
without it, pausing queues alone is insufficient. Re-run the command after every
restart or deployment.

Resume only after the operational owner records the reconciliation result and
accepts any residual risk:

```bash
/app/bin/storyarn rpc '
queues = [:imports, :imports_maintenance, :snapshot_archives, :snapshot_restores,
  :snapshot_imports, :snapshots_maintenance, :storage_cleanup]
Enum.each(queues, fn queue -> :ok = Oban.resume_queue(queue: queue) end)
states = Enum.map(queues, fn queue ->
  case Oban.check_queue(queue: queue) do
    nil -> %{queue: queue, paused: :not_running, limit: 0, running_count: 0}
    state -> %{queue: queue, paused: state.paused, limit: state.limit,
      running_count: length(state.running)}
  end
end)
IO.inspect(states, label: "Recovery queues resumed")
'
```

Never delete or rewrite Oban rows, cleanup receipts, reconciliation findings, or
snapshot ownership rows to make a drill pass.

### Yarn replacement rollout and containment

Exact project-snapshot restore and Yarn replacement do not have runtime feature
flags. They are normal authorized product capabilities. Their safety boundary
is the verified snapshot identity, the current-project checksum fence, and the
single final replacement transaction.

For the initial rollout, apply the migration before starting replacement-aware
application processes and avoid accepting imports until every `imports` queue
consumer runs the new release. The database completion fence prevents an older
worker from committing a replacement as an additive import, but pausing the
queue avoids needless retries while processes are mixed.

For incident containment, put the import surface into maintenance and pause the
`imports` queue. Cancel ready or queued attempts through the supported import
cancellation path and let running or retrying attempts settle; do not edit
attempts or Oban rows by hand. A final transaction that has already acquired
its locks may complete atomically.

Recovery snapshots are retained only for completed replacements. Failed,
cancelled, and expired replacements request cooperative cancellation while a
snapshot is still building, or create an `abandoned_import` cleanup intent once
it is terminal. The import-maintenance sweep reconciles any cleanup missed by a
process crash. Do not delete the snapshot row or provider objects by hand; the
cleanup intent is the durable ownership handoff that releases accounted storage
and removes the exact object inventory.

Before rolling application code or the replacement migration back, block new
imports, pause queue consumers, and verify that no replacement attempt remains
active:

```sql
SELECT status, stage, count(*)
FROM project_import_attempts
WHERE import_mode = 'replace_project'
  AND status IN ('ready', 'queued', 'running', 'retrying')
GROUP BY status, stage
ORDER BY status, stage;
```

Wait for the query to return no rows. The migration `down` path also takes an
exclusive table lock and aborts when it finds active replacement work. Only
after the query and migration guard pass may the older application release be
started and the queue resumed.

The cleanup-reason migration also refuses to roll back while an
`abandoned_import` cleanup intent exists. Those rows are durable audit and
ownership records, so do not delete them merely to force a rollback. Once this
cleanup path has been used, prefer a forward fix unless a separately reviewed
cleanup-history migration makes the older schema truthful again.

Monitor the low-cardinality, content-free import metrics by `import_mode`,
especially snapshot transitions and execute/error outcomes. Filenames, project
IDs, user IDs, and imported content must never be added as tags.

Provider lifecycle rules must not expire ready snapshot namespaces outside the
application protocol. Maintain external immutable object backup, access
boundaries, and a tested PostgreSQL restore drill. Reconciliation and the
real-provider smoke do not replace provider or database disaster recovery.
