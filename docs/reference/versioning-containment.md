# Snapshot lifecycle and reset runbook

> Owner: Engineering
>
> Last reviewed: 2026-08-05
>
> Source of truth: `lib/storyarn/versioning.ex`,
> `lib/storyarn/versioning/project_snapshot_lifecycle.ex`,
> `lib/storyarn/versioning/project_snapshot_reset.ex`,
> `lib/storyarn/release.ex`, and `lib/storyarn/workers/`

This runbook covers the one-time reset of pre-canonical versioning data and the
steady-state lifecycle of canonical full project snapshots. There is no runtime
reader, restore path, or compatibility branch for data removed by the reset.

## Steady-state guarantees

- Every full snapshot owns immutable ready and staging namespaces. Deletion
  records the exact manifest-derived inventory in both a cleanup ownership
  receipt and a `snapshot_cleanup_intents` row before removing the snapshot row
  or any parent project/workspace.
- Lifecycle transitions are forward-only and generation-fenced in both Ecto and
  PostgreSQL. A stale build, cancellation, retry, finalizer, or cleanup delivery
  cannot publish, regress, or apply an I/O result to a newer generation.
- Quota is released only after cleanup ownership is durable. The sole exception
  is a reservation proven never to have started storage; that release does not
  depend on object deletion.
- Cleanup uses bounded batches of at most 1,000 keys, durable checkpoints, exact
  worker-and-queue recovery, and duplicate-safe claim generations. Provider or
  namespace failures retain their remaining inventory for an explicit replay;
  invalid inventory or ownership fails closed for manual repair. All terminal
  failures remain visible in cleanup backlog metrics.
- Project/workspace hard deletion fails closed before loading more than the
  configured 1,000-snapshot parent inventory. Delete snapshots in smaller
  audited batches before retrying the parent operation.
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
  Restore staging and export/download staging must adopt the same reservation
  ownership protocol in their respective delivery tickets.

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

Deploy the prerequisite reset release first, before any image containing
migration `20260805130000`, or explicitly apply migrations only through the
receipt schema. The prerequisite release contains no lifecycle migration, so
its normal `Storyarn.Release.migrate()` is not blocked by missing receipts. In
the later lifecycle release, `Storyarn.Release.migrate()` applies through the
receipt schema, verifies the completed rollout, and only then permits migration
`20260805130000`. Ordinary development/test `mix ecto.migrate` remains a schema
operation and does not invoke this production release gate. The targeted
preparation command is:

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
   `STORYARN_DEPLOYMENT_ENVIRONMENT=production` in the lifecycle release and run
   its normal `Storyarn.Release.migrate()`. The release fails closed before
   migration `20260805130000` unless the latest workspace and provider receipts
   pass the same verifier above; once that migration is already applied,
   subsequent deploys do not repeat the one-time gate.
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
