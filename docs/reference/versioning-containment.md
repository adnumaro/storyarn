# Snapshot lifecycle and reset runbook

> Owner: Engineering
>
> Last reviewed: 2026-08-05
>
> Source of truth: `lib/storyarn/versioning.ex`,
> `lib/storyarn/versioning/project_snapshot_lifecycle.ex`,
> `lib/storyarn/versioning/project_snapshot_reset.ex`, and
> `lib/storyarn/workers/`

This runbook covers the one-time reset of pre-canonical versioning data and the
steady-state lifecycle of canonical full project snapshots. There is no runtime
reader, restore path, or compatibility branch for data removed by the reset.

## Steady-state guarantees

- Every full snapshot owns immutable ready and staging namespaces. Deletion
  records the exact manifest-derived inventory in both a cleanup ownership
  receipt and a `snapshot_cleanup_intents` row before removing the snapshot row
  or any parent project/workspace.
- Lifecycle transitions are forward-only and generation-fenced in both Ecto and
  PostgreSQL. A stale build, cancellation, retry, or finalizer cannot publish or
  regress a newer generation.
- Quota is released only after cleanup ownership is durable. The sole exception
  is a reservation proven never to have started storage; that release does not
  depend on object deletion.
- Cleanup is bounded, checkpointed, duplicate-safe, and retried by
  `CleanupProjectSnapshotWorker`. A terminal failure retains its exact remaining
  inventory for operator action and remains visible in cleanup backlog metrics.
  Project/workspace hard deletion fails closed before loading more than the
  configured 1,000-snapshot parent inventory; delete snapshots in smaller
  audited batches before retrying the parent operation.
- Retention candidates are selected in bounded keyset pages and all policy facts
  are revalidated under the workspace, project, and snapshot locks. User-created
  snapshots require explicit deletion; the current system TTLs are 30 days for
  daily snapshots, 14 days for pre-restore snapshots, and 30 days for
  post-restore snapshots.
- Reservation expiry is never deletion authority by itself. Maintenance removes
  an expired incomplete build only after its owning Oban job is terminal or
  absent, then repeats every identity and job-state check under lock.
- Linked snapshots fail closed until their reachability contract is implemented.
  Restore staging and export/download staging must adopt the same reservation
  ownership protocol in their respective delivery tickets.

## One-time pre-canonical reset

The reset is environment- and workspace-scoped. Its JSON plan is the durable
audit and retry receipt: it contains exact database row IDs, exact provider keys
with sizes and immutable provider identities, a SHA-256 digest binding the
environment, workspace, projects, row inventory, prefixes, and objects,
progress checkpoints, authorization digest, and final zero-state evidence. It
covers project snapshots plus entity
versions and their `project`, `sheet`, `flow`, `scene`, ready-object-set, and
staging-object-set namespaces. It never lists or deletes current project assets,
asset blobs, or another workspace.

The already-released accounting migration `20260804120000` intentionally reset
pre-canonical `project_snapshots` and `entity_versions` rows, but it could not
prove that remote provider objects were deleted. The reset therefore inventories
snapshot roots from the workspace's projects and remains useful when its row
inventories are empty. The ENG-80 lifecycle migration `20260805130000` fails if
versioning rows remain or any workspace lacks an immutable
`project_snapshot_reset_receipts` row whose ordered project inventory still
matches that workspace. The reset refuses to prepare or execute after that
migration has applied. There is no post-rollout reset mode or compatibility
branch.

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
   (43 characters without padding). Configure only its lowercase SHA-256 digest as
   `STORYARN_SNAPSHOT_RESET_AUTHORIZATION_SHA256`; store the value itself in an
   owner-only file mounted only in the one-off maintenance process.
4. Pre-create the plan directory in restricted durable storage with owner-only
   permissions (`0700`); the reset refuses missing, symlinked, or group/world
   accessible plan directories. Retain the provider inventory and database
   backup independently. Confirm PostgreSQL point-in-time recovery and provider
   recovery/versioning before making a user durability claim.

The reset calls the configured storage adapter directly. This is a narrow,
documented maintenance carve-out from the normal storage facade, whose deletion
guard deliberately blocks recoverable versioning objects. The carve-out is safe
only under the global write fence above. R2 has no conditional `DeleteObject`;
the adapter verifies the recorded ETag immediately before delete, but that check
and delete are not one atomic provider operation. Do not execute until the
credential fence has been independently verified. Retain an external immutable
backup of the reviewed inventory because R2 deletion is otherwise irreversible.
Provider evidence: [R2 S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/)
and [R2 consistency](https://developers.cloudflare.com/r2/reference/consistency/).

### Dry run and execution

First apply only the receipt prerequisite and earlier migrations. This command
stops at `20260805125000`; it never applies the lifecycle migration:

```text
/app/bin/storyarn eval 'Storyarn.Release.prepare_project_snapshot_reset_schema()'
```

The prerequisite may apply the already-released accounting reset, so database
row inventories can legitimately be empty. A normal all-migrations run now
fails closed at `20260805130000` until every current workspace has a receipt.

Run the dry run once for every workspace from the exact release image. The
command starts only the repository and storage HTTP runtime needed by the
maintenance function; it does not require Mix in the production image:

```text
/app/bin/storyarn eval \
  'Storyarn.Release.prepare_project_snapshot_reset("production", 42, "/secure/audit/snapshot-reset-workspace-42.json")'
```

Review the workspace, project IDs, snapshot and entity-version row counts,
object count, total bytes, immutable object identities, exact project snapshot
roots, database-inventory digest, and inventory digest in the plan. Do not
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
closed. On failure, keep the same plan and rerun the same command; never
regenerate a plan to conceal a changed scope. A completed plan is safe to replay
before rollout and must match its receipt.

### Deployment and verification

After every workspace has a completed plan:

1. Query the environment globally and require zero `project_snapshots` and zero
   `entity_versions`:

   ```sql
   SELECT count(*) AS project_snapshots FROM project_snapshots;
   SELECT count(*) AS entity_versions FROM entity_versions;
   SELECT count(*) AS missing_reset_receipts
   FROM workspaces w
   LEFT JOIN project_snapshot_reset_receipts r ON r.workspace_id = w.id
   WHERE r.workspace_id IS NULL;
   SELECT version FROM schema_migrations WHERE version >= 20260805130000 ORDER BY version;
   ```

   All three counts must be zero and the migration query must return no rows.
   Independently re-list every `projects/{id}/snapshots/` provider prefix and
   require zero objects and zero bytes.

2. Apply migrations and deploy all nodes without a mixed-version window.
3. Resume queues only after every node runs the same release.
4. Confirm no legacy versioning jobs remain and no reset authorization secret is
   present in the normal application environment.
5. Monitor cleanup backlog count/bytes, oldest age, retry count, terminal
   failures, retention failures, expired-build cleanup, and reset completion.

Engineering on-call owns the rollout and stores the completed plan, SQL output,
provider zero-inventory output, image digest, and timestamps together. Page
immediately for any terminal cleanup failure, reset failure, identity mismatch,
unexpected prefix, or provider-list error. Page when cleanup backlog oldest age
exceeds 15 minutes or count/bytes increase on two consecutive five-minute
samples. Keep queues paused and escalate to the storage owner for any provider
identity or recovery failure; involve Product/Support before making any user
durability statement.

Relevant telemetry prefixes are:

```text
storyarn.snapshot.cleanup.intent
storyarn.snapshot.cleanup.stop
storyarn.snapshot.retention.stop
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

Provider lifecycle rules must not expire canonical ready or staging namespaces
outside the application protocol. Verify external immutable object backup,
access boundaries, and a tested PostgreSQL restore drill. Application cleanup
receipts prove ownership and retry state; they do not replace provider or
database disaster recovery.

## Rollback rule

Pause and drain the same queues before rollback. The ENG-80 migration restores
the preceding constraints, but deleted pre-canonical data is intentionally not
reconstructed. Do not reintroduce a legacy reader or compatibility branch as a
rollback mechanism.
