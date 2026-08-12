# Entity-version restore integrity

> Owner: Engineering
>
> Last reviewed: 2026-08-12
>
> Source of truth: `Storyarn.Versioning.VersionCrud`, `RestorePolicy`, and the
> Sheet, Flow, and Scene snapshot builders

Storyarn restores named entity versions in place for Sheets, Flows, and Scenes.
These operations are separate from full-project snapshot restore. Each surface
has its own fail-closed runtime switch and remains disabled by default:

```text
SHEET_VERSION_RESTORE_ENABLED=false
FLOW_VERSION_RESTORE_ENABLED=false
SCENE_VERSION_RESTORE_ENABLED=false
```

Setting one switch to the literal value `true` enables only that entity type.
It does not enable either of the other entity restores or project-snapshot
restore.

## Common restore boundary

The product UI authorizes every preview and mutation with `:edit_content`.
Context-level restore functions are a trusted service boundary and may record a
`nil` actor for an internal operation; they do not replace route authorization.

Before a builder can mutate state, `VersionCrud.restore_version/4` verifies:

- the requested entity type, entity ID, and project ID;
- ownership of the persisted `EntityVersion` row;
- the canonical entity-version storage key;
- the compressed snapshot size and SHA-256 checksum; and
- that the call did not start inside an ambient database transaction.

It then creates, persists, reloads, and verifies a mandatory safety version of
the current entity. Inside the restore transaction, the builder locks that
safety-version row and compares the current entity snapshot with the verified
safety snapshot under the project, root, child-scope, reference, and applicable
localization locks. A missing or changed safety row, or a current edit that is
not represented by the safety snapshot, aborts before restore writes.

Any operation that may recreate an asset first takes the workspace storage lock
and then the project row lock. This matches the canonical asset-writer order and
prevents a restore from deadlocking against an upload or asset-trash operation.
After that boundary, authoritative Sheet, Flow, Scene, reference, and trash
writers serialize on the same project row before locking roots and children, so
a restore cannot publish mixed state. Nested rows use their historical IDs, and
ownership checks reject IDs belonging to another root or project.

## Reference and invariant matrix

| Surface | Reference                                                                                | Required restore behavior                                                                                                                                                                                                                     |
| ------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sheet   | Avatar, banner, and gallery assets                                                       | Reuse an active same-project asset only when its fingerprint matches. A missing historical asset may be recreated only from a size- and hash-verified snapshot catalog owned by the same project.                                             |
| Sheet   | Block reference values and rich-text mentions                                            | Target Sheet or Flow must be active and in the same project. The authoritative reference tracker locks and normalizes the value before any Sheet write.                                                                                       |
| Sheet   | Inherited and hidden block IDs                                                           | Source block and owning Sheet must be active and in the same project. Internal historical IDs are restored exactly; external inheritance is preserved only after graph and ownership checks. Cycles and ambiguous trash cascades fail closed. |
| Sheet   | Avatar backlinks                                                                         | An avatar absent from the selected version is removed only when no active or pending-trash reference requires it; otherwise the complete restore aborts.                                                                                      |
| Flow    | Backdrop Scene, speaker/location Sheet, referenced Flow, and terminal Scene/Flow targets | Every target must be active, in the same project, and locked. Flow cycles, invalid terminal targets, jump hubs, and dynamic exit pins fail before mutation.                                                                                   |
| Flow    | Speaker avatar                                                                           | The avatar must belong to the resolved active speaker Sheet. Snapshot and localization speaker mappings use the same Sheet identity map.                                                                                                      |
| Flow    | Rich-text mentions                                                                       | Every nested Sheet or Flow mention must resolve to an active same-project target before node data is written. The persisted graph and entity-reference index use the same normalized node payload.                                            |
| Flow    | Node audio, sequence track/layer, and localization voice assets                          | Node audio, sequence tracks, and localization voice-over require `audio/*`; sequence visual layers require `image/*`. Reuse or recreation also enforces same-project ownership, hash, size, and canonical-blob checks.                        |
| Flow    | Instruction and condition variables                                                      | Sheet shortcuts and variable paths must resolve to an active same-project block, including table row/column paths, before the graph or variable-reference index changes.                                                                      |
| Flow    | Localization actors                                                                      | `translated_by_id` and `reviewed_by_id` must identify existing users. Users are global identities and therefore are not project-scoped.                                                                                                       |
| Scene   | Background, pin icon, and zone label icon assets                                         | The asset must be an active same-project `image/*`, or be recreated from a verified same-project image catalog entry. Other content types fail closed.                                                                                        |
| Scene   | Pin Sheet/Flow; zone Flow/Scene target; collection-item Sheet                            | Targets must be active and in the same project.                                                                                                                                                                                               |
| Scene   | Ambient Flow                                                                             | The Flow must be active and in the same project; duplicate and foreign ambient identities fail before mutation.                                                                                                                               |
| Scene   | Pin, zone, and ambient-trigger variables                                                 | Conditions, assignments, display-variable paths, and `on_event` ambient-flow triggers must resolve to active same-project blocks before child rows and variable-reference indexes are reconciled.                                             |

The conflict preview applies the same active-project boundary for Sheets, Flows,
Scenes, assets, and inherited blocks. It is advisory only: builders repeat the
checks with row locks and remain the authoritative boundary. After successful
reconciliation, entity and variable reference indexes are rebuilt from the
persisted active graph before the transaction commits.

For assets, preview validates the snapshot catalog, fingerprint, project, size,
and slot-specific MIME family without performing object-storage I/O. A deleted
asset with a complete catalog entry can therefore remain restoreable in the UI;
the builder still verifies canonical blob existence and size before writing and
rolls the restore back if the object is unavailable or inconsistent.

## Exact nested-state policy

| Surface | Selected-version state                                                                                                                                          | Current-only state                                                                                                                                                                                                      | Existing trash and unrelated roots                                                                                                                                                                                                                                                                                                           |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sheet   | Restores versioned root fields, blocks, table rows and columns, gallery images, avatars, inheritance state, hidden inherited IDs, references, and localization. | Active blocks absent from the version are soft-deleted and their localization is archived. Target-block table/gallery children are reconciled exactly. Extra avatars are physically removed only after backlink checks. | Root hierarchy placement is current-only and is not moved by an entity-version restore. Unrelated Sheets and unrelated inherited instances are unchanged. Pre-existing block trash is not treated as current state; a historical ID is reactivated only when the selected version owns it and the inheritance/trash contract is unambiguous. |
| Flow    | Restores versioned root fields, nodes, connections, sequence configuration/tracks/layers, references, and localization on stable node IDs.                      | Active nodes absent from the version are soft-deleted; their localization is archived. Connections and sequence children for selected nodes are reconciled exactly.                                                     | Root hierarchy placement is current-only and is not moved by an entity-version restore. Unrelated Flows and pre-existing node trash remain unchanged. Incoming dynamic-pin callers are locked and validated before an exit can change.                                                                                                       |
| Scene   | Restores versioned root fields, layers, pins, zones, annotations, connections, ambient Flows, and reference indexes.                                            | Child rows absent from the version are physically removed and the selected child graph is recreated or updated by historical ID. Scene children do not have an entity-version trash lifecycle.                          | Root hierarchy placement is current-only and is not moved by an entity-version restore. Other Scenes are unchanged. A Scene root in trash cannot be restored through entity-version restore.                                                                                                                                                 |

All three roots and their projects must be active. Entity-version restore does
not double as Trash restore.

## Localization

Sheet and Flow snapshots carry localization rows plus a deterministic manifest
that binds row count, target locales, and SHA-256 digest. Schema, manifest,
duplicate, locale, source, speaker, voice-asset, and actor validation completes
before localization writes. Source IDs and reference IDs use the same identity
maps as the owning Sheet blocks or Flow nodes. Extraction and persistence run in
the restore transaction; any failure rolls back the entity graph and
localization together.

Target locales created after the historical version are reconciled by the
current target-locale contract rather than silently omitted. Unrelated archived
locale rows remain archived.

Scenes intentionally contain no localization payload. The runtime localization
source contract is limited to `sheet`, `block`, and `flow_node`.

## Storage compensation and retries

PostgreSQL rollback cannot roll back object-storage copies. Builders therefore
materialize assets through a shared copy tracker and cache:

1. copied objects are registered before database commit;
2. a failed transaction deletes unretained copies immediately;
3. a failed cleanup is persisted as a durable storage-compensation request;
4. successful commit retains only objects referenced by the committed graph;
5. repeated references to the same source fingerprint resolve to one
   destination asset and blob.

Project/root locks serialize duplicate restore attempts. Stable historical IDs,
exact ownership checks, and upsert/reconciliation rules prevent duplicate child
rows and reference-index entries. Each accepted attempt still creates its own
mandatory safety version; serialization is not version-history deduplication.

## Enablement decision

The code-level contracts are independent, and their tests can be evaluated per
surface. Production defaults remain disabled: this change does not silently
activate a mutating recovery path. An operator may enable one surface after the
deployed revision passes that surface's builder, policy, authorization,
rollback, and reference tests in the target environment. A failed surface stays
off without affecting the other two.

Full-project canonical v2 restore remains owned by ENG-76 and must consume these
proven primitives without weakening their project, safety-version, reference,
localization, or compensation boundaries.
