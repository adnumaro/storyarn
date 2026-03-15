# PR2 - Extract a First-Class References Context

## Goal

Create a dedicated `Storyarn.References` context that owns:

- entity reference tracking
- backlinks aggregation
- variable reference tracking
- variable usage reporting
- stale reference detection and repair

This PR removes reference-specific SQL and write logic from `Sheets`, `Flows`, `Scenes`, and `Screenplays`.

## Why This PR Exists

Reference behavior is currently split across:

- [lib/storyarn/sheets/reference_tracker.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/sheets/reference_tracker.ex)
- [lib/storyarn/flows/variable_reference_tracker.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/variable_reference_tracker.ex)
- reference-specific query helpers in `SheetQueries`, `SceneCrud`, `FlowCrud`, and `ScreenplayQueries`

This has produced drift in the actual contracts:

- [lib/storyarn/sheets/entity_reference.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/sheets/entity_reference.ex#L27) still validates `map_pin` and `map_zone`
- [lib/storyarn/flows/variable_reference.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/variable_reference.ex#L19) still validates `flow_node` and `map_zone`
- the write paths actually persist `scene_pin` and `scene_zone`
- the entity reference schema only documents `sheet` and `flow` targets, while scene links are already tracked from scene elements

This PR makes the contract explicit and central.

## Hard Decisions

These decisions are fixed for this PR.

1. The new facade module is `Storyarn.References`.
2. Canonical source types are:
   - `block`
   - `flow_node`
   - `screenplay_element`
   - `scene_pin`
   - `scene_zone`
3. Canonical entity reference target types are:
   - `sheet`
   - `flow`
   - `scene`
4. Canonical variable reference source types are:
   - `flow_node`
   - `scene_pin`
   - `scene_zone`
5. There will be no `map_pin` or `map_zone` identifiers after this PR.
6. Context facades may call `Storyarn.References.*`; they must not call another context's internal reference query helpers.
7. `insert_all` may still be used for bulk inserts, but the schemas and docs must match the values actually being persisted.

## Out of Scope

Do not include:

- breaking the current UI behavior of backlinks or variable usage
- changing reference extraction semantics beyond normalizing contracts
- changing sheet variable resolution rules
- performance optimizations unrelated to references
- new user-facing features

## Success Criteria

This PR is complete only when all of the following are true:

- `Storyarn.References` exists and is the only public owner of reference logic
- `Sheets`, `Flows`, `Scenes`, and `Screenplays` no longer expose public reference-specific SQL helper APIs
- schema docs, changesets, and persisted values use the same canonical type names
- there is a migration that rewrites any legacy `map_*` source types to `scene_*`
- `mix precommit` passes

## New Context Structure

Create this exact structure:

```text
lib/storyarn/references.ex
lib/storyarn/references/
├── entity_reference.ex
├── variable_reference.ex
├── entity_tracker.ex
├── variable_tracker.ex
├── backlinks.ex
└── variable_usage.ex
```

## Public API to Expose

Implement the facade in [lib/storyarn/references.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/references.ex) with `defdelegate`.

Required public functions:

### Entity references

- `update_block_references/1`
- `delete_block_references/1`
- `update_flow_node_entity_references/1`
- `delete_flow_node_entity_references/1`
- `update_screenplay_element_references/1`
- `delete_screenplay_element_references/1`
- `update_scene_pin_entity_references/1`
- `delete_scene_pin_entity_references/1`
- `update_scene_zone_entity_references/1`
- `delete_scene_zone_entity_references/1`
- `delete_target_references/2`
- `get_backlinks/2`
- `get_backlinks_with_sources/3`
- `count_backlinks/2`

### Variable references

- `update_flow_node_variable_references/1`
- `delete_flow_node_variable_references/1`
- `update_scene_pin_variable_references/2`
- `delete_scene_pin_variable_references/1`
- `update_scene_zone_variable_references/2`
- `delete_scene_zone_variable_references/1`
- `get_variable_usage/2`
- `count_variable_usage/1`
- `referenced_block_ids/1`
- `check_stale_variable_references/2`
- `repair_stale_variable_references/1`
- `list_stale_node_ids/1`

Do not expose context-internal helpers beyond this list.

## Files That Must Move or Be Rewritten

### Move into `Storyarn.References`

- [lib/storyarn/sheets/entity_reference.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/sheets/entity_reference.ex)
- [lib/storyarn/flows/variable_reference.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/variable_reference.ex)
- entity-tracking logic from [lib/storyarn/sheets/reference_tracker.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/sheets/reference_tracker.ex)
- variable-tracking logic from [lib/storyarn/flows/variable_reference_tracker.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/variable_reference_tracker.ex)

### Delete after migration

- `Storyarn.Sheets.ReferenceTracker`
- `Storyarn.Flows.VariableReferenceTracker`

### Migrate reference-specific read helpers out of other contexts

Move or inline into `Storyarn.References` the reference-specific query code currently living in:

- [lib/storyarn/flows/flow_crud.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/flow_crud.ex)
- [lib/storyarn/scenes/scene_crud.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/scenes/scene_crud.ex)
- [lib/storyarn/screenplays/screenplay_queries.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/screenplays/screenplay_queries.ex)
- [lib/storyarn/sheets/sheet_queries.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/sheets/sheet_queries.ex)

## Required Data Migration

Add a migration under `priv/repo/migrations/` with this exact purpose:

- update `entity_references.source_type`
  - `map_pin -> scene_pin`
  - `map_zone -> scene_zone`
- update `variable_references.source_type`
  - `map_pin -> scene_pin`
  - `map_zone -> scene_zone`

Use SQL `UPDATE` statements via `execute/1`.

Do not rename tables.
Do not rename columns.
Do not add enums or check constraints in this PR.

## Ordered Execution Plan

### Phase 0 - Baseline

Before editing, record:

```bash
mix test
mix compile
```

### Phase 1 - Create the new context

1. Add [lib/storyarn/references.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/references.ex)
2. Add [lib/storyarn/references/entity_reference.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/references/entity_reference.ex)
3. Add [lib/storyarn/references/variable_reference.ex](/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/references/variable_reference.ex)
4. Move code into:
   - `entity_tracker.ex`
   - `variable_tracker.ex`
   - `backlinks.ex`
   - `variable_usage.ex`

Required canonical schema changes:

### `EntityReference`

- `@source_types ~w(block flow_node screenplay_element scene_pin scene_zone)`
- `@target_types ~w(sheet flow scene)`

### `VariableReference`

- `@source_types ~w(flow_node scene_pin scene_zone)`

Update module docs to match the canonical values.

### Phase 2 - Move write paths

Replace callers in these contexts:

- `Sheets`
- `Flows`
- `Scenes`
- `Screenplays`

Required replacements:

- any call to `Storyarn.Sheets.ReferenceTracker.*` becomes `Storyarn.References.*`
- any call to `Storyarn.Flows.VariableReferenceTracker.*` becomes `Storyarn.References.*`

Keep all existing facade APIs in the owning contexts intact unless they are reference-specific helper functions listed for deletion.

### Phase 3 - Move backlinks query ownership

Move the SQL for enriched backlinks into `Storyarn.References.Backlinks`.

After the move, delete these public helper functions if they exist:

- `Flows.query_flow_node_backlinks/3`
- `Screenplays.query_screenplay_element_backlinks/3`
- `Scenes.query_scene_pin_backlinks/3`
- `Scenes.query_scene_zone_backlinks/3`

`Storyarn.References.Backlinks` is allowed to import and join against `FlowNode`, `Flow`, `ScreenplayElement`, `Screenplay`, `ScenePin`, `SceneZone`, `Scene`, `Block`, and `Sheet` directly. That is the correct boundary for this PR.

### Phase 4 - Move variable usage and stale-reference query ownership

Move reference-specific SQL out of `SheetQueries` and `SceneCrud` into `Storyarn.References.VariableUsage`.

At minimum, move the logic behind:

- variable usage for scene pins and scene zones
- stale scene pin variable reference checks
- stale scene zone variable reference checks
- stale flow node variable reference checks
- repair queries that currently live under `Sheets`
- stale node ID listing for flows

Do not move plain sheet-domain lookup functions such as:

- block resolution by sheet shortcut and variable name
- table block resolution by variable path

Those stay in `Sheets`, and `Storyarn.References.VariableTracker` may call them through the `Sheets` facade.

### Phase 5 - Add the source-type normalization migration

Create and run the migration that rewrites legacy `map_*` values.

Verify:

```bash
mix ecto.migrate
mix test
```

### Phase 6 - Delete legacy tracker modules

Only after all callers compile and tests pass:

- delete `Storyarn.Sheets.ReferenceTracker`
- delete `Storyarn.Flows.VariableReferenceTracker`

Then remove any stale aliases and docs references.

## File-by-File Caller Expectations

### `Sheets`

After this PR:

- `Sheets` may still resolve variables and sheet IDs
- `Sheets` must not own backlink aggregation
- `Sheets` must not own stale variable repair SQL

### `Flows`

After this PR:

- `Flows` may still interpret node data semantics
- `Flows` must not own polymorphic variable reference persistence
- `Flows` must not expose reference-specific query helpers

### `Scenes`

After this PR:

- `Scenes` may still own scene CRUD
- `Scenes` must not own backlink SQL
- `Scenes` must not own variable usage SQL

### `Screenplays`

After this PR:

- `Screenplays` may still own screenplay CRUD and flow sync
- `Screenplays` must not own backlink SQL for entity references

## Test Plan

Add or update tests to cover all of the following:

### Entity references

- block rich-text mention creates sheet backlink
- flow node speaker and mention create backlinks
- screenplay character and mention create backlinks
- scene pin target and display sheet create backlinks
- scene zone target and action-data sheet usage create backlinks
- backlinks aggregation returns enriched source info for all source types

### Variable references

- flow node instruction writes are persisted
- flow node condition reads are persisted
- scene pin instruction writes and display reads are persisted
- scene zone instruction writes and display reads are persisted
- variable usage returns flow, pin, and zone sources
- stale reference checks still work
- repair updates node JSON and leaves unaffected nodes untouched

### Migration

Add a migration test or post-migration assertion that legacy `map_*` rows are rewritten.

## Commands to Run

Run all of these before finishing:

```bash
mix ecto.migrate
mix test
mix compile
mix precommit
```

## Commit Plan

Use this order:

1. `create references context and move schemas`
2. `move entity tracking into references`
3. `move variable tracking into references`
4. `move backlinks and variable usage queries into references`
5. `normalize legacy source types via migration`
6. `delete legacy tracker modules and cleanup`

## Reviewer Checklist

- `Storyarn.References` is the single owner of references
- no caller still aliases the old tracker modules
- canonical type names are consistent in docs, code, and writes
- scenes are accepted as entity-reference targets
- legacy `map_*` values are cleaned up

## Rollback Plan

If the migration or context extraction proves unstable:

1. keep the new schema modules
2. revert the deletion of legacy tracker modules
3. leave the new facade in place as a compatibility layer
4. restore callers to the legacy modules temporarily

Do not roll back the data normalization migration once it has run in shared environments.
