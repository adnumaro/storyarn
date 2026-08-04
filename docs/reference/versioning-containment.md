# Version-control containment rollout

> Owner: Engineering
>
> Last reviewed: 2026-08-04
>
> Source of truth: `lib/storyarn/versioning.ex`, `lib/storyarn/versioning/project_snapshot.ex`, the project settings LiveViews, and `lib/storyarn_web/controllers/snapshot_download_controller.ex`

This runbook deploys the canonical project-snapshot persistence boundary while
capture, restore, deletion, retention, and download workflows remain unavailable.

## Code guarantee

With every node running this release:

- Project-snapshot capture, restore, deletion, recovery, and download reject
  before reading or mutating snapshot storage, acquiring locks, or enqueueing work.
- The rollout deletes existing project-snapshot rows before enforcing the
  canonical versioned identity; legacy gzip rows and object keys are unsupported.
  The migration does not delete remote objects, so operators must purge them
  before the database reset removes their inventory.
- Legacy project-snapshot workers and schedules do not exist in this release.
- Entity trash and deleted-project snapshots are not purged automatically.
- Content-addressed recovery blobs under `projects/{id}/blobs/` cannot be
  deleted through compensation cleanup or the shared storage deletion boundary.
- Missing, malformed, and non-boolean entity-restore switch values fail closed.

The containment does not disable explicit authorized deletion of entity
versions, projects, workspaces, or trash items. Project snapshot create,
restore, delete, and download surfaces remain disabled until their canonical
lifecycle tickets are connected. Template installation remains available and
intentionally uses project materialization independently of deleted-project
recovery.

## Entity restore environment

Keep all values explicitly disabled:

```text
SHEET_VERSION_RESTORE_ENABLED=false
FLOW_VERSION_RESTORE_ENABLED=false
SCENE_VERSION_RESTORE_ENABLED=false
ENTITY_TRASH_RETENTION_ENABLED=false
```

Runtime configuration is read during node startup. Changing environment
variables without restarting every node does not change the effective policy.

## Safe deployment sequence

1. Pause the `default`, `snapshots`, and `project_restores` Oban queues on every
   running node and wait for executing jobs to finish.
2. Delete queued project-snapshot capture, restore, recovery, and retention jobs;
   this rollout intentionally provides no compatibility executor for them.
3. Outside the application, export and retain an exact provider inventory for
   `projects/*/snapshots/project/*.json.gz`, including object key, size, and
   checksum/ETag when available. Reconcile it with the pre-reset
   `project_snapshots` rows while those mappings still exist.
4. Delete every object in that exact legacy namespace with provider tooling.
   Re-list the namespace independently and require a zero-object result. Do not
   deploy the migration, resume queues, or use an application legacy reader
   until the verified inventory is zero.
5. Set and independently verify every environment value listed above.
6. Deploy or restart every application node; do not use a mixed-version rolling
   window because the database migration resets project-snapshot rows.
7. Inspect effective application configuration on a new node and confirm every
   entity restore value is literal `false`.
8. Confirm no old application node remains registered or receiving traffic.
9. Inspect `storage_cleanup_requests`. Quarantine any cleanup key under
   `/assets/` that is still referenced by `assets.key`.
10. Resume the remaining queues.
11. Verify that project-snapshot and deleted-project recovery controls are absent,
    downloads return a uniform not-found response, and no snapshot worker is scheduled.

## External storage prerequisite

Before making a production retention guarantee, inspect the Cloudflare R2
bucket outside this repository:

- Inventory historical recovery objects and confirm blob keys use the canonical
  `projects/{positive_id}/blobs/...` prefix.
- Blob and snapshot prefixes must not have lifecycle expiration or another
  provider-side deletion policy.
- The application credential must not be able to bypass the storage facade and
  delete the blob prefix; use provider-side versioning or immutability controls
  when available.

Record the result alongside the deployment evidence.

## Database and alerting prerequisites

Preserving object bytes alone does not preserve database IDs, references, or
snapshot metadata. Confirm PostgreSQL point-in-time recovery is active and
complete a restore drill before claiming recoverability.

Alert on these telemetry events so attempted safety-boundary violations are
visible:

```text
storyarn.assets.storage.invalid_delete_blocked
storyarn.assets.storage.recoverable_blob_delete_blocked
storyarn.assets.storage_compensation.recoverable_blob_cleanup_blocked
```

## Rollback rule

Do not re-enable a switch merely to roll back this release. Restore operations
remain destructive until their corresponding integrity work has passed its own
audit cycle. Roll back only after pausing and draining the same queues again.
