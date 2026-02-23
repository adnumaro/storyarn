# Performance Audit

## Score: 72/100

## Findings

### Critical (High Impact)

**C1. Recursive N+1 in `PropertyInheritance.get_descendant_sheet_ids/1`**
File: `lib/storyarn/sheets/property_inheritance.ex:288-299`
Fires one query per tree level per branch. For 5 levels deep with 20 children/level → 100+ queries.
**Fix:** Recursive CTE.

**C2. Recursive N+1 in `PropertyInheritance.build_ancestor_list/1`**
File: `lib/storyarn/sheets/property_inheritance.ex:369-383`
One `Repo.get` per ancestor level. Same in `SheetQueries.build_ancestor_chain/2:650-662`.
**Fix:** Single recursive CTE query.

**C3. N+1 in `TableCrud` cell manipulation**
File: `lib/storyarn/sheets/table_crud.ex:630-686`
`add_cell_to_all_rows/2`, `remove_cell_from_all_rows/2`, `migrate_cells_key/3`, `reset_cells_for_column/2` — load all rows then update one-by-one. With inheritance sync: 50 sheets × 20 rows = 1000+ updates.
**Fix:** `Repo.update_all` with PostgreSQL JSONB operators.

**C4. Recursive N+1 in `SheetQueries.preload_children_recursive/1`**
File: `lib/storyarn/sheets/sheet_queries.ex:664-680`
O(N) queries for sidebar tree where N = number of sheets.
**Fix:** Load all project sheets in one query, build tree in memory (like `FlowCrud.list_flows_tree` already does).

**C5. N+1 in `Localization.Reports.progress_by_language/1`**
File: `lib/storyarn/localization/reports.ex:13-33`
One query per language. 10 languages = 10 queries.
**Fix:** Single `GROUP BY locale_code, status`.

### Warnings (Medium Impact)

- `SoftDelete.soft_delete_children/4` — recursive query + individual updates per child
- `PropertyInheritance.cleanup_hidden_block_ids/1:535-547` — individual updates per sheet
- `PropertyInheritance.dedup_variable_names_for_sheet/3:512-524` — individual `Repo.update_all` per block
- `TextExtractor.extract_all/1:164-260` — individual upserts per field × locale
- `ReferenceTracker` — individual `Repo.insert(on_conflict: :nothing)` in loops (should use `Repo.insert_all`)
- `Screenplays.FlowSync.load_descendant_data/2:557-572` — recursive loading level by level
- `BlockCrud.reorder_blocks/2` and `reorder_blocks_with_columns/2` — individual position update per block
- `PropertyInheritance.copy_table_structure_to_instances/1:627-643` — queries count per instance
- Flow canvas serializes entire flow to HTML attribute (large DOM payload)

### Good Patterns

- Deferred loading with `start_async` in Flow editor
- Batch `batch_resolve_subflow_data/1` and `batch_resolve_interaction_data/1` (2 queries for all references)
- JOINs in all backlink queries
- Comprehensive indexing: composites, partial unique, FK indexes
- `batch_load_table_data/1` — two queries for all columns+rows across blocks
- In-memory tree building for flows (`list_flows_tree`)
- Topic-scoped PubSub (no fan-out)
- Selective preloading (`get_flow_brief` vs `get_flow!`)
- Proper `select` usage avoiding full schema loads
