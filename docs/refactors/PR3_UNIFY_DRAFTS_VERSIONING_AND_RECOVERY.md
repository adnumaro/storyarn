# PR3 - Unify Drafts, Versioning, and Recovery Around Snapshot Builders

## Goal

Make snapshot builders the only source of truth for copy-and-restore operations across:

- draft creation
- draft merge preparation
- project recovery
- entity materialization from stored snapshots

This PR removes bespoke row-cloning logic as an architectural pattern. Drafts may remain materialized rows for editing, but they must be created through the same builder-based snapshot pipeline used by versioning and recovery.

## Why This PR Exists

Today the project has multiple overlapping mechanisms:

- [lib/storyarn/drafts/clone_engine.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/drafts/clone_engine.ex) deep-clones rows directly
- [lib/storyarn/drafts/merge_engine.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/drafts/merge_engine.ex) converts draft rows back into snapshots and restores them
- [lib/storyarn/versioning/builders/project_snapshot_builder.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/builders/project_snapshot_builder.ex) already treats snapshots as the canonical export format
- [lib/storyarn/versioning/project_recovery.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/project_recovery.ex) manually re-inserts data and remaps IDs

That duplication creates two problems:

1. copy semantics are implemented more than once
2. any schema evolution must be updated in multiple places

This PR collapses those paths into one builder-driven materialization system.

## Hard Decisions

These decisions are fixed.

1. Drafts continue to use the existing `drafts` table and editable materialized rows in `sheets`, `flows`, and `scenes`.
2. `CloneEngine` stops being a handwritten row cloner. It becomes a thin compatibility wrapper around builder-based snapshot materialization.
3. `ProjectRecovery` stops manually inserting entity rows field-by-field. It uses the same builder-based materialization contracts.
4. Snapshot builders gain a new callback:

```elixir
instantiate_snapshot(project_id, snapshot, opts)
```

5. Existing in-place restore callback remains:

```elixir
restore_snapshot(entity, snapshot, opts)
```

6. This PR does not rewrite editors to work on raw JSON snapshots.
7. This PR does not remove `draft_id` from entity tables.
8. Screenplay draft fields in [lib/storyarn/screenplays/screenplay.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/screenplays/screenplay.ex#L14) are explicitly out of scope for this PR. Do not touch them here.

## Out of Scope

Do not include:

- redesigning the draft UX
- removing draft URLs or changing draft routing
- migrating editors to non-materialized drafts
- visual diff work
- cleanup of inactive screenplay draft fields

## Success Criteria

This PR is complete only when all of the following are true:

- creating a draft no longer depends on handwritten `Repo.insert_all` clone trees
- project recovery no longer depends on handwritten per-table insertion logic
- `SheetBuilder`, `FlowBuilder`, and `SceneBuilder` can all materialize new entities from snapshots
- draft creation and project recovery both go through builder-based materialization
- `mix precommit` passes

## Required Architecture

### 1. Extend the snapshot builder behavior

Update the behavior used by:

- [lib/storyarn/versioning/builders/sheet_builder.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/builders/sheet_builder.ex)
- [lib/storyarn/versioning/builders/flow_builder.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/builders/flow_builder.ex)
- [lib/storyarn/versioning/builders/scene_builder.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/builders/scene_builder.ex)

Add a new callback:

```elixir
@callback instantiate_snapshot(
  project_id :: integer(),
  snapshot :: map(),
  opts :: keyword()
) ::
  {:ok, struct(), map()} | {:error, term()}
```

Return shape:

- first element: the newly created root entity
- second element: an ID map with old child IDs to new child IDs

Required ID map keys:

### Sheet builder

- `sheet`
- `block`

### Flow builder

- `flow`
- `node`
- `connection`

### Scene builder

- `scene`
- `layer`
- `zone`
- `pin`
- `connection`
- `annotation`

### 2. Builder materialization options

All three builders must support these options where applicable:

- `draft_id: integer() | nil`
- `parent_id: integer() | nil`
- `position: integer() | nil`
- `reset_shortcut: boolean()`
- `preserve_shortcut: boolean()`
- `preserve_external_refs: boolean()`

Rules:

1. `reset_shortcut: true` means the new entity gets `shortcut: nil`
2. `preserve_shortcut: true` means the snapshot shortcut is reused
3. `draft_id` is written onto the root entity
4. all materialized child rows must also receive the correct `draft_id` behavior if their schema supports it through the root relation
5. external references such as linked sheet IDs, scene IDs, asset IDs, and referenced flow IDs are preserved unless explicitly remapped by the caller

### 3. New shared helper module

Create:

```text
lib/storyarn/versioning/materialization_helpers.ex
```

This module owns common patterns that are currently duplicated between clone and recovery code:

- timestamp generation
- bulk insert helper wrappers
- ordered insert-with-returning helpers
- old-to-new ID map builders
- optional shortcut reset logic

Do not place these helpers under `Drafts`. They belong to the versioning materialization layer.

## Exact Implementation Plan

### Phase 0 - Baseline and safety

Record the current behavior:

```bash
mix test
mix compile
```

Search for all handwritten clone and recovery insertion sites:

```bash
rg -n "Repo.insert_all|returning: \\[:id\\]|old_new_map|id_map|clone_" lib/storyarn/drafts lib/storyarn/versioning
```

Use that output to verify all clone-style logic is removed or replaced by the end of the PR.

### Phase 1 - Extend builder contracts

1. Update the shared snapshot builder behavior module
2. Add `instantiate_snapshot/3` to:
   - `SheetBuilder`
   - `FlowBuilder`
   - `SceneBuilder`

Implementation requirements:

#### `SheetBuilder.instantiate_snapshot/3`

- insert one root sheet row
- optionally reset shortcut
- insert all blocks from the snapshot
- restore table columns and table rows
- remap intra-sheet block inheritance
- return `%{sheet: %{old_sheet_id => new_sheet_id}, block: %{old_block_id => new_block_id}}`

#### `FlowBuilder.instantiate_snapshot/3`

- insert one root flow row
- optionally reset shortcut
- insert nodes in snapshot order
- insert connections after node ID remap
- preserve scene foreign key only if `preserve_external_refs: true`
- return `%{flow: %{old_flow_id => new_flow_id}, node: ..., connection: ...}`

#### `SceneBuilder.instantiate_snapshot/3`

- insert one root scene row
- optionally reset shortcut
- insert layers first
- insert zones, then pins, then connections, then annotations
- remap internal scene references using the new layer and pin IDs
- preserve linked sheet and flow targets unless caller overrides them later
- return `%{scene: ..., layer: ..., zone: ..., pin: ..., connection: ..., annotation: ...}`

### Phase 2 - Reimplement draft creation on top of builders

Keep the public API of [lib/storyarn/drafts/draft_crud.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/drafts/draft_crud.ex) unchanged.

Required changes:

1. `DraftCrud.create_draft/5` must load the source entity as today
2. it must resolve the current source version number via `Versioning.get_latest_version/2`
3. it must create the `Draft` record first
4. it must call builder-based materialization through `CloneEngine`

`CloneEngine` must remain as the adapter used by `DraftCrud`, but it must no longer contain handwritten deep-clone SQL.

Required new `CloneEngine` shape:

- select builder by `entity_type`
- build snapshot from source entity
- call `builder.instantiate_snapshot(project_id, snapshot, draft_id: draft.id, reset_shortcut: true, preserve_external_refs: true)`
- load and return the materialized draft entity

### Phase 3 - Move baseline merge metadata to snapshot-derived helpers

Keep `baseline_entity_ids` in `Draft` because merge logic still uses it.

However, derive it from snapshots, not from live clone SQL.

Create:

```text
lib/storyarn/drafts/baseline_ids.ex
```

Required behavior:

- `sheet` drafts store block IDs from the snapshot as `%{"block_ids" => [...]}` using snapshot `original_id` values
- `flow` and `scene` drafts return `%{}`

Update `DraftCrud` to use this helper.

Do not leave raw SQL in `CloneEngine` for baseline extraction.

### Phase 4 - Reimplement project recovery on top of builders

Refactor [lib/storyarn/versioning/project_recovery.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/project_recovery.ex).

Required end state:

1. `ProjectRecovery` still orchestrates project creation, owner membership, tree restoration, and localization restore
2. it no longer owns handwritten entity insertion logic for sheets, flows, or scenes
3. instead, for each snapshot entry it calls the relevant builder's `instantiate_snapshot/3`

Required recovery strategy:

- materialize all sheets first
- materialize all flows second
- materialize all scenes third
- collect and merge their ID maps into a single `id_maps` structure
- run centralized cross-entity remapping after materialization
- restore tree hierarchy after all roots exist
- restore localization last

### Phase 5 - Centralize cross-entity remapping in recovery

Keep remapping orchestration inside `ProjectRecovery`, but move any helper logic that is purely ID-map-based into private helper modules if the file becomes too large.

Allowed new helper files:

```text
lib/storyarn/versioning/project_recovery/remapper.ex
lib/storyarn/versioning/project_recovery/tree_restorer.ex
```

Use these only if [project_recovery.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/project_recovery.ex) would otherwise exceed a reasonable review size.

Required remaps:

- flow node links that reference other flows or sheets
- scene pin and zone targets that reference sheets, flows, or scenes
- intra-snapshot block inheritance
- localization foreign keys pointing to remapped sheets or assets where applicable

### Phase 6 - Remove handwritten clone logic

After builder materialization is working:

- delete the per-entity handwritten clone internals from `CloneEngine`
- delete the handwritten insertion helpers from `ProjectRecovery`
- keep only wrapper/orchestration code

At the end of the PR there must be no direct row-clone implementation left that duplicates builder snapshot semantics.

## Required Non-Behavioral Guarantees

### Draft behavior must remain the same

After this PR:

- draft URLs still open the same editors
- draft entities still live in the same tables with `draft_id`
- draft merge still uses the existing merge flow
- active draft visibility rules do not change

### Recovery behavior must remain the same

After this PR:

- project recovery still creates a new project
- project recovery still restores trees and localization
- project recovery still remaps internal IDs safely

## Files That Must Change

At minimum:

- [lib/storyarn/versioning/snapshot_builder.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/snapshot_builder.ex)
- [lib/storyarn/versioning/builders/sheet_builder.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/builders/sheet_builder.ex)
- [lib/storyarn/versioning/builders/flow_builder.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/builders/flow_builder.ex)
- [lib/storyarn/versioning/builders/scene_builder.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/builders/scene_builder.ex)
- [lib/storyarn/versioning/project_recovery.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/versioning/project_recovery.ex)
- [lib/storyarn/drafts/clone_engine.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/drafts/clone_engine.ex)
- [lib/storyarn/drafts/draft_crud.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/drafts/draft_crud.ex)
- [lib/storyarn/drafts/merge_engine.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/drafts/merge_engine.ex)

New files expected:

- `lib/storyarn/versioning/materialization_helpers.ex`
- `lib/storyarn/drafts/baseline_ids.ex`

Optional helper files only if needed:

- `lib/storyarn/versioning/project_recovery/remapper.ex`
- `lib/storyarn/versioning/project_recovery/tree_restorer.ex`

## Test Plan

Add or update tests for all of the following:

### Builder materialization

- sheet builder can instantiate a new sheet from a snapshot
- flow builder can instantiate a new flow from a snapshot
- scene builder can instantiate a new scene from a snapshot
- each returns a correct ID map

### Draft creation

- creating a sheet draft produces a materialized draft through the builder path
- creating a flow draft preserves external refs and remaps internal refs
- creating a scene draft remaps layers, pins, connections, and annotations correctly
- `source_version_number` is set when a latest version exists

### Draft merge

- merge behavior remains unchanged after the clone-path replacement
- pre-merge and post-merge snapshots are still created

### Project recovery

- recovery builds a new project through builder materialization
- tree hierarchy is restored correctly
- cross-entity references are remapped correctly
- localization restore still works

## Commands to Run

Run all of these before finishing:

```bash
mix test
mix compile
mix precommit
```

If the repo has targeted tests for drafts or versioning, run them first while iterating:

```bash
mix test test/storyarn/drafts* test/storyarn/versioning*
```

## Commit Plan

Use this order:

1. `extend snapshot builder behavior with instantiate_snapshot`
2. `implement builder materialization for sheets flows and scenes`
3. `rebuild draft creation on top of builder materialization`
4. `derive draft baseline ids from snapshots`
5. `rebuild project recovery on top of builder materialization`
6. `remove handwritten clone and recovery insertion logic`

## Reviewer Checklist

- new builder callback exists and is implemented everywhere required
- draft creation no longer depends on handwritten clone trees
- recovery no longer manually inserts entity rows field-by-field
- materialization returns deterministic ID maps
- no product behavior changed for draft editing or merge

## Rollback Plan

If this refactor becomes unstable:

1. keep the new builder callback in place
2. revert `CloneEngine` to the previous implementation
3. revert `ProjectRecovery` to the previous implementation
4. leave tests for `instantiate_snapshot/3` in place for a follow-up PR

Do not partially merge the draft changes without the recovery refactor. This PR only makes sense if both copy paths are unified.
