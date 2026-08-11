# Project snapshot lifecycle runbook

> Owner: Engineering
>
> Last reviewed: 2026-08-11
>
> Source of truth: `lib/storyarn/versioning/project_snapshot_lifecycle.ex`,
> `lib/storyarn/versioning/snapshot_archive_storage.ex`,
> `lib/storyarn/versioning/snapshot_archive_smoke.ex`,
> `lib/storyarn/versioning/project_snapshot_reconciliation.ex`,
> `lib/storyarn/versioning/project_snapshot_reconciliation_repair.ex`,
> `lib/storyarn/assets/storage/`, `lib/storyarn/release.ex`, and
> `lib/storyarn/workers/`, plus
> `priv/repo/migrations/20260811180000_make_project_snapshots_v2_only.exs`

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
exists. Its preflight locks the relevant lifecycle tables and requires all of
the following to be absent:

- non-v2 or non-full project snapshot rows;
- v1 publication claims;
- linked-conversion or v1-owned storage reservations;
- linked or v1 cleanup intents;
- live cleanup requests containing v1 or linked-conversion keys;
- active `BuildProjectSnapshotWorker` jobs in any queue; or
- active generic cleanup jobs carrying retired snapshot keys.

The current production assumption is that these sets are already empty because
no project snapshots have been created. If the migration reports an active
build, let the pre-cutover deployment finish or settle it before retrying. If it
reports retired ownership, use that binary's durable cleanup protocol to purge
the owned provider bytes; do not delete database rows directly and leave R2
ownership orphaned. Terminal immutable cleanup receipts and namespace evidence
remain preserved for audit, but the replacement database trigger can never
create new retired-format evidence.

The runtime no longer maps, reads, or writes `project_storage_key` or
`source_asset_count`. Their physical columns remain nullable for this one
rolling-deploy boundary because the pre-cutover Ecto schemas still select them,
but database constraints require both values to remain `NULL`.
The immediately following release must drop both columns, after every
application machine is confirmed to be running the v2-only schema. Do not defer
that cleanup beyond the next release. These columns do not authorize v1 storage
or linked conversion.

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

Provider lifecycle rules must not expire ready snapshot namespaces outside the
application protocol. Maintain external immutable object backup, access
boundaries, and a tested PostgreSQL restore drill. Reconciliation and the
real-provider smoke do not replace provider or database disaster recovery.
