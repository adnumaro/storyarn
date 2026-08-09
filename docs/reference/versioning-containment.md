# Snapshot lifecycle and reset runbook

> Owner: Engineering
>
> Last reviewed: 2026-08-09
>
> Source of truth: `lib/storyarn/versioning/project_snapshot_lifecycle.ex`,
> `lib/storyarn/versioning/project_snapshot_reconciliation.ex`,
> `lib/storyarn/versioning/project_snapshot_reconciliation_repair.ex`,
> `lib/storyarn/versioning/project_snapshot_reset.ex`,
> `lib/storyarn/assets/storage/`, `lib/storyarn/release.ex`, and
> `lib/storyarn/workers/`

This runbook covers the one-time reset of pre-canonical versioning data and the
steady-state lifecycle of canonical full project snapshots. There is no runtime
reader, restore path, or compatibility branch for data removed by the reset.

## Steady-state guarantees

- Every full snapshot owns immutable ready and staging namespaces. Before any
  snapshot or parent deletion, Storyarn durably records its exact manifest
  inventory in a cleanup receipt and `snapshot_cleanup_intents` row.
- Lifecycle transitions are forward-only and generation-fenced in both Ecto and
  PostgreSQL. A stale build, cancellation, retry, finalizer, or cleanup delivery
  cannot publish, regress, or apply an I/O result to a newer generation.
- Quota release requires durable cleanup ownership, except for a reservation
  proven never to have started storage.
- Cleanup uses bounded batches of at most 1,000 keys, durable checkpoints, exact
  worker-and-queue recovery, and duplicate-safe claim generations. Provider or
  namespace failures retain their remaining inventory for an explicit replay;
  invalid inventory or ownership fails closed for manual repair. All terminal
  failures remain visible in cleanup backlog metrics. Parent deletion also
  fails closed above the configured 1,000-snapshot inventory.
- Retention candidates are selected in bounded keyset pages. Every destructive
  decision is revalidated under the workspace, project, and snapshot locks with
  PostgreSQL time as the expiry authority. User-created snapshots require
  explicit deletion.
- Reservation expiry is never deletion authority by itself. Maintenance removes
  an expired incomplete build only after its exact Oban job is terminal or
  absent and quiescent. Cleanup then performs two delete-and-verify passes,
  separated by a PostgreSQL-enforced minimum of 15 minutes, so a delayed writer
  cannot make a namespace ready or escape the second pass.
- Linked snapshots fail closed until their reachability contract is implemented.

## Observation-only reconciliation

Snapshot reconciliation is an operator-started dry-run. It verifies every
`ready` snapshot that existed at the run's database high-watermark, compares
its immutable row, manifest, publication claim, committed reservation, exact
ready namespace, sizes, MIME metadata, and streamed SHA-256 digests, and then
performs a resumable provider scan under `projects/`. It also records quiescent
expired build reservations, terminal cleanup intents, malformed reserved-root
keys, unowned canonical namespaces, and abandoned temporary namespaces. It
does not update integrity state, settle reservations, retry cleanup, delete or
copy objects, or change quota. A persisted finding is a repair candidate, not
mutation authority by itself.

Start the inspection on a running release node and inspect its bounded finding
pages with:

```text
/app/bin/storyarn rpc 'Storyarn.Release.start_project_snapshot_reconciliation()'
/app/bin/storyarn rpc 'Storyarn.Release.inspect_project_snapshot_reconciliation(123, 0, 100)'
```

Only one run may be active for a physical provider namespace. Work is delivered
manually through the existing `snapshots_maintenance` queue at lower priority
than retention and cleanup. Every continuation is generation-fenced; its
cursor, monotonic counters, and immutable deduplicated findings commit together.
If the current-generation job is discarded after exhausting retries or a node
crash prevents terminal evidence from being committed, run the start command
again: it returns the same active run and idempotently restores that exact
generation's queue delivery once an `executing` job is older than the worker
timeout plus its recovery margin. A new run captures all database
high-watermarks behind a short `NOWAIT` source-table barrier; if a writer is
active, start fails closed and the operator must retry rather than accept a
partial identity view.
The configured per-step object/byte budgets, provider page size, total provider
object/byte limits, finding limit, malformed pages, same-page cursors,
non-monotonic keys, provider namespace changes, ready-snapshot generation
changes, and provider failures all fail closed. An opaque cursor cycle that does
not repeat on adjacent pages cannot evade the total object/byte caps. There is
deliberately no cron schedule in this phase.

Provider key checkpoints use PostgreSQL binary values so legal object keys that
contain NUL bytes cannot block the scan. When such a key cannot be stored safely
as text evidence, the finding preserves it as a labeled base64url value.

`completed` means the bounded database and ListObjects inspection finished. It
does not mean the physical inventory is exhaustive: the current storage
contract cannot enumerate incomplete multipart uploads, so each run persists
`multipart_inventory_state = unsupported` and
`physical_inventory_complete = false`. Never interpret that state as zero
multipart drift or as repair/deletion authority. Findings called ambiguous or
abandoned are investigation candidates only; the repair pass must reacquire
ownership locks and revalidate all evidence.

The run emits low-cardinality `snapshot.reconciliation.start`, `.page`,
`.summary`, and `.stop` telemetry and logs terminal failure codes.
Reconciliation intentionally does not call the workspace-wide
provider-footprint metric with snapshot-only bytes, because that would compare
different accounting scopes.

## Fenced reconciliation repair

Repair consumes immutable findings from a completed inspection, but treats
their recorded evidence as stale until proven otherwise. Integrity repair takes
the workspace advisory lock and snapshot row lock before matching the recorded
generations and repeating the provider read. Expired-build repair delegates to
the existing lifecycle primitive and its workspace, project, snapshot,
reservation, and job fences. Cleanup replay locks the intent and revalidates its
exact evidence, immutable inventory, ownership receipt, and provider namespace.
Report-only actions do not acquire mutation locks because they cannot change
state. A changed or already-resolved subject is a successful no-op; it must
never be forced back to the old finding.

Actions are durable and one-shot for one immutable finding and repair contract.
A later inspection can produce a new action for recurring evidence without
reopening or rewriting the earlier outcome. Terminal outcomes are immutable:
`repaired` means that the
generation-fenced mutation or durable cleanup handoff committed, `resolved`
means the current state no longer needs that action, `manual` means the required
safety proof could not be established, and `failed` means the bounded action
ended in an operational error. Retrying a delivered action must converge on the
same outcome without duplicating quota settlement, cleanup ownership, or
provider deletion.

| Finding category                                                                                                                 | Automated action when current evidence is exact                                                                  | Manual boundary                                                                                                                                                                    |
| -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ready_manifest_missing`, `ready_object_missing`                                                                                 | `mark_missing` after the ready snapshot and missing object are revalidated under the recorded generations        | Any identity, ownership, lifecycle, or provider result changed                                                                                                                     |
| `ready_manifest_corrupt`, `ready_object_corrupt`                                                                                 | `mark_corrupt` after the exact bytes, size, and digest failure are reverified                                    | A replacement object appeared, the snapshot changed, or corruption cannot be reproduced                                                                                            |
| `stale_reservation`                                                                                                              | `cleanup_expired_build` only for the same expired, quiescent build with no live owner or publication path        | Live or ambiguous job, claim, generation, namespace, or cleanup proof                                                                                                              |
| `failed_snapshot_finalization`                                                                                                   | `cleanup_expired_build` only when it converges on that same independently revalidated expired-build contract     | Every other finalization shape is report-only                                                                                                                                      |
| `terminal_cleanup_failure`                                                                                                       | `replay_cleanup` only for a still-terminal intent with a replayable provider failure and exact durable inventory | Invalid inventory, invalid ownership, namespace ownership, or another integrity failure                                                                                            |
| `abandoned_temporary_object`                                                                                                     | `report_only`                                                                                                    | The current inspection records key and size but no durable conditional-delete identity. Automatic deletion would be unsafe if the object were replaced with the same key and size. |
| `ready_database_manifest_mismatch`, `ready_inventory_mismatch`, `ready_accounting_mismatch`, `ready_verification_limit_exceeded` | `report_only`                                                                                                    | These divergences do not provide enough evidence for automatic data or accounting reconstruction                                                                                   |
| `ambiguous_storage_object`, `unsafe_snapshot_storage_key`, or any unknown category                                               | `report_only`                                                                                                    | Require explicit investigation and a separately reviewed repair plan                                                                                                               |

The repair pass does not improve physical-inventory completeness. Incomplete
multipart uploads remain invisible to the current storage contract, so
`multipart_inventory_state = unsupported` and
`physical_inventory_complete = false` remain mandatory even after every known
finding is repaired. Provider lifecycle configuration, multipart inventory and
abort operations, and alerts for residual multipart bytes are separate
provider-operations prerequisites; never substitute a zero application gauge
for that evidence.

After repairs and their durable cleanup jobs settle, always start a new dry-run
and inspect its new findings. Do not reuse the repaired run as readiness proof.
The post-repair run must independently converge, and any remaining critical,
manual, terminal-cleanup, stale-reservation, or orphan-object signal remains an
operator decision. `physical_inventory_complete = false` still prevents a claim
of exhaustive physical reconciliation.

Plan repair actions in bounded finding pages, then inspect their durable
outcomes with:

```text
/app/bin/storyarn rpc 'Storyarn.Release.repair_project_snapshot_reconciliation(123, 0, 50)'
/app/bin/storyarn rpc 'Storyarn.Release.inspect_project_snapshot_reconciliation_repairs(123, 0, 100)'
```

The first command is not another preview: it persists each action and
immediately enqueues its asynchronous repair delivery. Use only a completed
inspection whose findings have been reviewed against the matrix above.

Continue with the returned cursor until `complete: true`. Wait for every action
to reach a terminal outcome before starting the next dry-run. `manual` and
`failed` outcomes require explicit operator review; planning a later completed
inspection creates a separate action instead of rewriting prior evidence.

The metrics catalog includes repair counts and bytes by low-cardinality
`action`/`outcome`, summary gauges for stale reservation bytes, orphan object
bytes, missing or corrupt ready snapshots, and terminal cleanup failures and
retries, plus cleanup-backlog gauges for terminal retries and repeated terminal
failures. `orphan_object_bytes` counts only
`abandoned_temporary_object` evidence; ambiguous objects are deliberately
excluded because their ownership is not proven. Storyarn still has no production reporter, dashboard, retention
policy, or alert routing in this repository. Connecting these metrics to the
deployment observability system and defining escalation for non-zero critical
or repeated-terminal signals is a prerequisite to claiming automated alerts;
the catalog alone is not an alert.

## One-time pre-canonical reset

The reset has two ordered scopes. A workspace plan contains every versioning row
currently attributable to that workspace and the exact provider keys under its
current projects. After all workspace plans complete, one environment-global
provider plan scans `projects/` and captures every remaining strict snapshot
object, including roots orphaned by deleted projects or workspaces. Both plan
types contain sizes and immutable provider identities, a unique plan ID, a
SHA-256 digest binding the complete scope, an opaque fingerprint of the storage
adapter and physical namespace, bounded progress checkpoints, authorization
audit metadata, and final zero-state evidence. They cover project snapshots plus
entity versions and their `project`, `sheet`, `flow`, `scene`, ready-object-set,
and staging-object-set namespaces. They never list for deletion or delete current
project assets or asset blobs.

The already-released accounting migration `20260804120000` intentionally removed
pre-canonical database rows before this tooling existed. This reset cannot and
does not reconstruct or claim an historical inventory of those deleted rows. It
proves the current database zero-state and independently inventories all provider
snapshot roots, which that migration could not verify.

Each successful workspace plan appends an immutable
`project_snapshot_reset_receipts` revision. The global plan appends an immutable
`project_snapshot_provider_reset_receipts` revision with the inspected-object
count, the explicit scan limit, and the exact ordered IDs of the latest workspace
receipt revisions. That revision vector is part of the global plan digest and
makes any later workspace receipt or workspace-set change invalidate the global
sweep. A unique plan ID is part of both the receipt identity and inventory digest.
Retries of the same plan may use a fresh one-use
authorization token, which replaces the running plan's digest before a new
receipt is written. If execution already committed a receipt but failed to
persist its final plan checkpoint, recovery accepts fresh authorization but
restores the authorization digest, attempt number, and completion time from the
immutable receipt. A newly prepared plan always creates a new revision, and
rollout accepts only the latest exact workspace receipts and latest matching
environment-global provider receipt.

### Preconditions

1. Use the exact release commit, but do not apply ENG-80 migration
   `20260805130000` or any later snapshot migration.
2. Establish a real global write fence: stop every application node and queue
   worker, revoke every other R2 write credential, wait at least one minute for
   IAM propagation, and verify those credentials can no longer write. Then use
   only a one-off release `eval` process and maintenance credential. Pausing
   queues alone is insufficient because HTTP nodes can still create versions.
   Verify zero running nodes and zero executing snapshot/versioning jobs before
   inventory.
3. Set `STORYARN_DEPLOYMENT_ENVIRONMENT` to the exact deployment name. Generate
   a base64url one-use authorization token encoding at least 32 random bytes
   (43 characters without padding). Configure only its lowercase SHA-256 digest
   as `STORYARN_SNAPSHOT_RESET_AUTHORIZATION_SHA256`; store the value itself in
   an owner-only regular file mounted only in the one-off maintenance process.
   For a retry, rotate both the token file and configured digest. Never place the
   token itself in process environment variables.
4. Pre-create the plan directory in restricted durable storage with owner-only
   permissions (`0700`); the reset refuses missing, symlinked, or group/world
   accessible plan directories. Retain the provider inventory and database
   backup independently. Confirm PostgreSQL point-in-time recovery and provider
   recovery/versioning before making a user durability claim.
5. Before inventory, prove conditional delete against the exact production
   provider and maintenance credential. Use a unique sacrificial key outside
   `projects/` and every real application namespace. Upload one value and record
   its ETag, replace it and record the new ETag, then issue `DeleteObject` with
   `If-Match` set to the old ETag. Require HTTP 412 and independently verify that
   the replacement still exists unchanged. Repeat with the current ETag and
   require successful deletion. Clean up the probe and retain the request IDs,
   status codes, ETags, and verification output with the rollout evidence. Stop
   if either condition is not demonstrated; repository adapter tests are not a
   substitute for this provider probe.

The reset calls the configured storage adapter directly. This is a narrow,
documented maintenance carve-out from the normal storage facade, whose deletion
guard deliberately blocks recoverable versioning objects. The carve-out is safe
only under the global write fence above. R2 sends one conditional `DeleteObject`
with `If-Match`; an identity change fails closed instead of opening a HEAD/delete
race. The global credential fence is still mandatory because it also prevents
new snapshot objects and database scope changes during inventory and execution.
Retain an external immutable backup of the reviewed inventory because R2
deletion is otherwise irreversible.
Provider evidence: [R2 S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/)
and [R2 consistency](https://developers.cloudflare.com/r2/reference/consistency/).

### Dry run and execution

Deploy the prerequisite reset release before any image containing migration
`20260805130000`; it has only the receipt schema, so normal release migration is
unblocked. The lifecycle release applies that schema, verifies the rollout, and
then permits `20260805130000`. Development/test `mix ecto.migrate` remains
schema-only. The targeted preparation command is:

`Storyarn.Release.migrate/0` has one bootstrap path for a genuinely new
environment: when there are no workspaces, projects, versioning rows, or reset
receipt history, it scans at most one object under `projects/` and requires the
entire namespace to be empty. It then executes the normal zero-inventory
provider plan and persists its immutable provider receipt before authorizing the
lifecycle migration. Any workspace, project, versioning row, reset receipt,
provider object, list error, or unexpected response fails closed and requires
the reset ceremony above. In production, migration `20260805130000` also
rejects direct migration entrypoints; run it through
`Storyarn.Release.migrate/0` so the receipt check cannot be silently bypassed.

```text
/app/bin/storyarn eval 'Storyarn.Release.prepare_project_snapshot_reset_schema()'
```

The prerequisite may apply the already-released accounting reset, so current
database row inventories can legitimately be empty.

Run the dry run once for every workspace from the exact release image. The
command starts only the repository and storage HTTP runtime needed by the
maintenance function; it does not require Mix in the production image:

```text
/app/bin/storyarn eval \
  'Storyarn.Release.prepare_project_snapshot_reset("production", 42, "/secure/audit/snapshot-reset-workspace-42.json")'
```

Review the workspace, project IDs, snapshot and entity-version row counts,
storage-namespace fingerprint, object count, total bytes, immutable object
identities, exact project snapshot roots, database-inventory digest, and
inventory digest in the plan. Do not
execute if any path is outside the documented snapshot namespaces. Dry run
refuses to overwrite an existing plan, and plan files are created with
owner-only permissions.

Execute only with the reviewed digest:

```text
/app/bin/storyarn eval \
  'Storyarn.Release.execute_project_snapshot_reset("production", 42, "/secure/audit/snapshot-reset-workspace-42.json", "64_HEX_SHA256_DIGEST", "/run/secrets/snapshot-reset-authorization")'
```

The command verifies row fingerprints plus object size and immutable identity,
then deletes exact provider keys in bounded batches. It makes at most 32
inventory-progress checkpoints, so a 250,000-object plan remains linear in
audit-file I/O while preserving bounded replay after interruption. It re-lists
each complete `projects/{id}/snapshots/` root to zero, then deletes the recorded
database rows in one transaction, verifies the exact project scope and zero
versioning rows, and persists an immutable receipt before checkpointing the
completed plan. Any unknown current or future child namespace therefore fails
closed. On failure, keep the same plan and rerun with a newly authorized token;
never regenerate a plan to conceal a changed scope. A completed plan is safe to
replay before rollout and must match its immutable receipt revision.

### Global provider sweep

After every workspace has a completed plan, prepare the environment-global plan
with an explicit maximum number of provider objects to inspect. The scan is
paginated and bounded: every object seen under `projects/` consumes the limit,
but only keys matching `projects/{positive_id}/snapshots/...` are retained for
deletion. A malformed snapshot-looking key fails the plan; unrelated current
asset and blob keys are ignored for deletion.

```text
/app/bin/storyarn eval \
  'Storyarn.Release.prepare_project_snapshot_provider_reset("production", "/secure/audit/snapshot-reset-provider.json", 1000000)'
```

Review the storage-namespace fingerprint, ordered workspace receipt revision
IDs, scanned count, scan limit, object count, bytes, exact keys, identities, and
inventory digest. Choose the scan limit from an independently measured provider
inventory; do not raise it merely to bypass an unexpected result. Then execute
the reviewed global plan:

```text
/app/bin/storyarn eval \
  'Storyarn.Release.execute_project_snapshot_provider_reset("production", "/secure/audit/snapshot-reset-provider.json", "64_HEX_SHA256_DIGEST", "/run/secrets/snapshot-reset-authorization")'
```

The global plan may run only while both versioning tables are globally empty and
every current workspace has its latest exact receipt. It rechecks those facts
and the exact receipt-revision vector before execution and before committing its
own receipt. Any later workspace revision or workspace-set change requires a new
global plan. Any adapter, endpoint, bucket, or local-root change fails before
deletion and also invalidates rollout readiness. The Local adapter additionally
binds the absolute root to the device and inode of every existing directory in
its path; it rejects symlinked components, and records an explicit
missing-component marker so later creation or replacement also changes the
namespace. Retry only the same plan, with a rotated authorization token, if
execution checkpoints an error without such a scope change.

### Deployment and verification

After the environment-global provider plan has completed:

1. Query the environment globally and require zero `project_snapshots` and zero
   `entity_versions`:

   ```sql
   SELECT count(*) AS project_snapshots FROM project_snapshots;
   SELECT count(*) AS entity_versions FROM entity_versions;
   SELECT count(*) AS invalid_latest_reset_receipts
   FROM workspaces w
   LEFT JOIN LATERAL (
     SELECT environment, project_ids, storage_namespace_fingerprint
     FROM project_snapshot_reset_receipts
     WHERE workspace_id = w.id
     ORDER BY id DESC
     LIMIT 1
   ) r ON TRUE
   WHERE r.environment IS DISTINCT FROM 'production'
      OR r.storage_namespace_fingerprint IS DISTINCT FROM '64_HEX_STORAGE_NAMESPACE_FINGERPRINT'
      OR r.project_ids IS DISTINCT FROM ARRAY(
        SELECT p.id
        FROM projects p
        WHERE p.workspace_id = w.id
        ORDER BY p.id
      );
   WITH latest_workspace_receipts AS (
     SELECT DISTINCT ON (workspace_id) id, workspace_id
     FROM project_snapshot_reset_receipts
     ORDER BY workspace_id, id DESC
   ),
   current_receipt_vector AS (
     SELECT COALESCE(
       array_agg(r.id ORDER BY r.id) FILTER (WHERE r.id IS NOT NULL),
       ARRAY[]::bigint[]
     ) AS receipt_ids
     FROM workspaces w
     LEFT JOIN latest_workspace_receipts r ON r.workspace_id = w.id
   ),
   latest_provider_receipt AS (
     SELECT environment, workspace_receipt_ids, storage_namespace_fingerprint
     FROM project_snapshot_provider_reset_receipts
     ORDER BY id DESC
     LIMIT 1
   )
   SELECT count(*) AS invalid_latest_provider_receipts
   FROM current_receipt_vector receipt_vector
   LEFT JOIN latest_provider_receipt provider ON TRUE
   WHERE provider.environment IS DISTINCT FROM 'production'
      OR provider.storage_namespace_fingerprint IS DISTINCT FROM '64_HEX_STORAGE_NAMESPACE_FINGERPRINT'
      OR provider.workspace_receipt_ids IS DISTINCT FROM receipt_vector.receipt_ids;
   SELECT version FROM schema_migrations WHERE version >= 20260805130000 ORDER BY version;
   ```

   `ProjectSnapshotReset.verify_rollout_readiness/2` performs the receipt and
   database checks in one MVCC statement: both versioning tables must be
   globally empty, every workspace's highest receipt revision must match the
   exact environment, storage namespace, and current ordered project IDs, and
   the highest global provider receipt must match that same environment and
   storage namespace. Replace the SQL fingerprint placeholder with the value
   printed by the reviewed plan. All four SQL counts must be zero and the
   migration query must return no rows. The completed global plan is the
   bounded provider zero-inventory evidence, including orphan roots.

   Run the release verifier before applying the later lifecycle migration:

   ```text
   /app/bin/storyarn eval \
     'Storyarn.Release.verify_project_snapshot_reset_rollout("production")'
   ```

2. Keep the write fence in place. Set
   `STORYARN_DEPLOYMENT_ENVIRONMENT=production` and run
   `Storyarn.Release.migrate()`. It requires current receipts before first
   applying `20260805130000`; subsequent deploys skip the one-time gate.
3. Resume queues only after every node runs the same release.
4. Confirm no legacy versioning jobs remain and no reset authorization secret is
   present in the normal application environment.
5. Monitor reset completion and failures.

Engineering on-call owns the rollout and stores the completed plan, SQL output,
provider zero-inventory output, image digest, and timestamps together. Page
immediately for any reset failure, identity mismatch, unexpected prefix, or
provider-list error. Keep queues paused and escalate to the storage owner for any provider
identity or recovery failure; involve Product/Support before making any user
durability statement.

Relevant telemetry prefixes are:

```text
storyarn.snapshot.reset.stop
```

## Containment switches

Entity-version restore remains independently contained. Keep these exact
runtime values disabled throughout reset and rollout:

```text
SHEET_VERSION_RESTORE_ENABLED=false
FLOW_VERSION_RESTORE_ENABLED=false
SCENE_VERSION_RESTORE_ENABLED=false
ENTITY_TRASH_RETENTION_ENABLED=false
```

Runtime configuration is read at node startup. Changing these values without
restarting every node does not change effective policy. These switches do not
provide the reset write fence and must never substitute for scaling application
nodes to zero.

## External durability prerequisites

Provider lifecycle rules must not expire snapshot namespaces outside the
application protocol. Verify external immutable object backup, access boundaries,
and a tested PostgreSQL restore drill. Reset receipts prove one audited reset;
they do not replace provider or database disaster recovery.

## Rollback rule

Pause and drain the same queues before rollback. Deleted pre-canonical data is
intentionally not reconstructed. Do not reintroduce a legacy reader or
compatibility branch as a rollback mechanism.
