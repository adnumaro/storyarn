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
and sizes, a SHA-256 digest binding the environment, workspace, projects, rows,
prefixes, and objects, progress checkpoints, authorization digest, and final
zero-state evidence. It covers project snapshots plus entity
versions and their `project`, `sheet`, `flow`, `scene`, ready-object-set, and
staging-object-set namespaces. It never lists or deletes current project assets,
asset blobs, or another workspace.

The accounting migration fails if any pre-canonical `project_snapshots` or
`entity_versions` rows remain. It does not silently delete them.

### Preconditions

1. Use the exact release commit, but do not apply its versioning migrations yet.
2. Pause `snapshots`, `snapshots_maintenance`, `storage_cleanup`, and every old
   versioning/restore queue on all nodes. Drain executing jobs and prevent
   versioning writes for the target workspace.
3. Set `STORYARN_DEPLOYMENT_ENVIRONMENT` to the exact deployment name. Generate
   a one-use authorization value of at least 32 random bytes and expose it as
   `STORYARN_SNAPSHOT_RESET_AUTHORIZATION` only to the maintenance process.
4. Store plans in restricted durable storage. Retain the provider inventory and
   database backup independently. Confirm PostgreSQL point-in-time recovery and
   provider recovery/versioning before making a user durability claim.

### Dry run and execution

Run the dry run once for every workspace:

```text
mix storyarn.snapshots.reset \
  --environment production \
  --workspace-id 42 \
  --plan /secure/audit/snapshot-reset-workspace-42.json
```

Review the workspace, project IDs, snapshot and entity-version row counts,
object count, exact prefixes, and inventory digest in the plan. Do not execute
if any path is outside the documented snapshot namespaces. Dry run refuses to
overwrite an existing plan, and plan files are created with owner-only
permissions.

Execute only with the reviewed digest:

```text
STORYARN_SNAPSHOT_RESET_AUTHORIZATION=ONE_USE_SECRET \
mix storyarn.snapshots.reset \
  --environment production \
  --workspace-id 42 \
  --plan /secure/audit/snapshot-reset-workspace-42.json \
  --execute \
  --confirm-inventory 64_HEX_SHA256_DIGEST
```

The command deletes exact provider keys in bounded batches, checkpoints after
each batch, re-lists every prefix to zero, then deletes the recorded database
rows in one transaction and verifies the workspace has zero versioning rows.
On failure, keep the same plan and rerun the same command; never regenerate a
plan to conceal a changed scope. A completed plan is safe to replay.

### Deployment and verification

After every workspace has a completed plan:

1. Query the environment globally and require zero `project_snapshots` and zero
   `entity_versions`. Independently re-list all reset prefixes and require zero
   objects.
2. Apply migrations and deploy all nodes without a mixed-version window.
3. Resume queues only after every node runs the same release.
4. Confirm no legacy versioning jobs remain and no reset authorization secret is
   present in the normal application environment.
5. Monitor cleanup backlog count/bytes, oldest age, retry count, terminal
   failures, retention failures, expired-build cleanup, and reset completion.

Relevant telemetry prefixes are:

```text
storyarn.snapshot.cleanup.intent
storyarn.snapshot.cleanup.stop
storyarn.snapshot.retention.stop
storyarn.snapshot.reset.stop
```

## External durability prerequisites

Provider lifecycle rules must not expire canonical ready or staging namespaces
outside the application protocol. Verify bucket versioning or equivalent
recovery, access boundaries, and a tested PostgreSQL restore drill. Application
cleanup receipts prove ownership and retry state; they do not replace provider
or database disaster recovery.

## Rollback rule

Pause and drain the same queues before rollback. The ENG-80 migration restores
the preceding constraints, but deleted pre-canonical data is intentionally not
reconstructed. Do not reintroduce a legacy reader or compatibility branch as a
rollback mechanism.
