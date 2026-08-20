# Project snapshot lifecycle runbook

> Owner: Engineering
>
> Last reviewed: 2026-08-12
>
> Source of truth: `lib/storyarn/versioning/project_snapshot_lifecycle.ex`,
> `lib/storyarn/versioning/snapshot_archive_storage.ex`,
> `lib/storyarn/versioning/snapshot_archive_smoke.ex`,
> `lib/storyarn/versioning/project_snapshot_reconciliation.ex`,
> `lib/storyarn/versioning/project_snapshot_reconciliation_repair.ex`,
> `lib/storyarn/assets/storage/`, `lib/storyarn/release.ex`, and
> `lib/storyarn/workers/`, plus
> `priv/repo/migrations/20260811180000_make_project_snapshots_v2_only.exs` and
> `priv/repo/migrations/20260812100000_remove_transitional_snapshot_cutover_scaffolding.exs`

Project snapshots have one canonical representation: a v2 full ZIP archive and
its manifest sidecar. There is no runtime switch, alternate format, linked mode,
conversion path, or compatibility reader.

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
/app/bin/storyarn rpc 'Storyarn.Release.start_project_snapshot_reconciliation()'
/app/bin/storyarn rpc 'Storyarn.Release.inspect_project_snapshot_reconciliation(123, 0, 100)'
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
/app/bin/storyarn rpc 'Storyarn.Release.repair_project_snapshot_reconciliation(123, 0, 50)'
/app/bin/storyarn rpc 'Storyarn.Release.inspect_project_snapshot_reconciliation_repairs(123, 0, 100)'
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

2. Verify the bucket has a lifecycle rule that expires incomplete multipart
   uploads after a bounded period. This is provider-side defence in depth for a
   remote upload that outlives the local five-minute `UploadPart` deadline.
3. Create one small full snapshot with the deployed background worker and wait
   until it is `ready` and `verified`.
4. Run the read-only smoke on the release node:

   ```bash
   bin/storyarn rpc 'Storyarn.Versioning.SnapshotArchiveSmoke.run!(SNAPSHOT_ID)'
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

### Yarn replacement rollout and containment

Yarn whole-project replacement has two independent runtime controls:

```text
PROJECT_SNAPSHOT_RESTORE_ENABLED=false
YARN_IMPORT_REPLACE_ENABLED=false
```

`PROJECT_SNAPSHOT_RESTORE_ENABLED` is the fail-closed restore switch and a
mandatory execution prerequisite for replacement. `YARN_IMPORT_REPLACE_ENABLED`
is only a producer gate: disabling it prevents new replacement jobs, but does
not stop one that has already been accepted.

Keep both values disabled while deploying the replacement-capable release and
running its migrations. After every process consuming the `imports` queue is on
that release, complete the real-provider snapshot smoke above, enable project
snapshot restore, and then enable the Yarn producer gate. Do not enable the
producer while an older imports worker can still claim jobs.

For incident containment, disable `YARN_IMPORT_REPLACE_ENABLED` first. If an
accepted replacement must also stop, disable
`PROJECT_SNAPSHOT_RESTORE_ENABLED`; an execution that has not crossed the final
replacement gate then fails closed before project content is removed. A final
transaction already past that gate may still complete, so wait for active work
to settle. This also disables normal project-snapshot restores, so treat it as
the broader emergency switch.

Before rolling application code or this migration back, keep the producer gate
disabled and verify that no replacement attempt remains active:

```sql
SELECT status, stage, count(*)
FROM project_import_attempts
WHERE import_mode = 'replace_project'
  AND status IN ('ready', 'queued', 'running', 'retrying')
GROUP BY status, stage
ORDER BY status, stage;
```

Wait for the query to return no rows. Cancel ready or queued work through the
supported import cancellation path and let running or retrying work reach a
terminal state; do not edit attempts or Oban rows by hand. Re-enable the gates
only after all imports workers are current again. Monitor the
low-cardinality, content-free import metrics by `import_mode`, especially
snapshot transitions and execute/error outcomes; filenames, project IDs, user
IDs, and imported content must never be added as tags.

Provider lifecycle rules must not expire ready snapshot namespaces outside the
application protocol. Maintain external immutable object backup, access
boundaries, and a tested PostgreSQL restore drill. Reconciliation and the
real-provider smoke do not replace provider or database disaster recovery.
