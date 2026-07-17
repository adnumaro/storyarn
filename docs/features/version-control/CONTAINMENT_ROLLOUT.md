# Version-control containment rollout

This runbook deploys the beta containment layer that freezes unsafe restore and
automatic retention paths while referential-integrity fixes are developed.

## Code guarantee

With the safety switches below set to `false` and every node running this
release:

- Sheet, Flow, Scene, project-snapshot, and deleted-project restores reject
  before reading snapshot storage, creating backups, acquiring locks, enqueueing
  work, or mutating data.
- Already queued restore and recovery jobs reject again when they execute.
- Entity trash, automatic snapshots, and deleted-project snapshots are not
  purged automatically.
- Daily snapshot creation remains active; only pruning is frozen.
- Content-addressed recovery blobs under `projects/{id}/blobs/` cannot be
  deleted through compensation cleanup or the shared storage deletion boundary.
- Missing, malformed, and non-boolean switch values fail closed.

The containment does not disable explicit authorized deletion of versions,
snapshots, projects, workspaces, or trash items. Template installation remains
available and intentionally uses project materialization independently of
deleted-project recovery.

## Required environment

Keep all values explicitly disabled:

```text
SHEET_VERSION_RESTORE_ENABLED=false
FLOW_VERSION_RESTORE_ENABLED=false
SCENE_VERSION_RESTORE_ENABLED=false
PROJECT_SNAPSHOT_RESTORE_ENABLED=false
DELETED_PROJECT_RECOVERY_ENABLED=false
DELETED_PROJECT_SNAPSHOT_RETENTION_ENABLED=false
ENTITY_TRASH_RETENTION_ENABLED=false
AUTO_SNAPSHOT_PRUNING_ENABLED=false
```

Runtime configuration is read during node startup. Changing environment
variables without restarting every node does not change the effective policy.

## Safe deployment sequence

1. Pause the `default` and `snapshots` Oban queues on every running node.
2. Wait until neither queue has executing jobs. A job that started on the old
   release cannot observe the new guards.
3. Set and independently verify every environment value listed above.
4. Deploy or restart every application node; do not use a mixed-version rolling
   window for this rollout.
5. Inspect effective application configuration on a new node and confirm every
   restore and retention value is literal `false`.
6. Confirm no old application node remains registered or receiving traffic.
7. Inspect pending `executing`, `retryable`, and `scheduled` jobs plus
   `storage_cleanup_requests`. Quarantine any cleanup key under `/assets/` that
   is still referenced by `assets.key`.
8. Resume the queues.
9. Verify that restore/recovery controls are absent and that daily snapshot
   creation still succeeds without reducing the previous snapshot count.

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
