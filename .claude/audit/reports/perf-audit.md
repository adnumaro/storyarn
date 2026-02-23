# Performance Audit Report

**Project:** Storyarn
**Date:** 2026-02-23
**Score:** 72/100

---

## Executive Summary

The Storyarn codebase demonstrates solid query patterns in most areas, with good use of batch loading (e.g., `batch_resolve_subflow_data`), recursive CTEs for tree traversal, and proper PubSub topic scoping. However, several N+1 patterns, missing database indexes, monolithic JavaScript bundling, and absence of LiveView streams/temporary_assigns create performance risks that will scale poorly as projects grow.

---

## 1. N+1 Query Detection

### Critical

**C1: `MapCrud.list_ancestors/2` -- Sequential Repo.get in recursive loop**
- **File:** `lib/storyarn/maps/map_crud.ex` lines ~322-345
- **Impact:** Up to 50 sequential `Repo.get(Map, parent_id)` calls for deeply nested maps
- **Fix:** Replace with a recursive CTE query (same pattern used in `SheetQueries.list_ancestors`)

**C2: `BlockCrud.reorder_blocks/3` and `reorder_blocks_with_columns/3` -- N individual UPDATEs**
- **File:** `lib/storyarn/sheets/block_crud.ex` lines ~475-489 (reorder_blocks), lines ~404-424 (reorder_blocks_with_columns)
- **Impact:** Issues one UPDATE per block when reordering. For a sheet with 30 blocks, that is 30 DB round-trips
- **Fix:** Use `Repo.insert_all` with `on_conflict: :replace_all` or a single `CASE WHEN` UPDATE statement

**C4: `TextExtractor.extract_all/1` -- O(N*M) individual upserts**
- **File:** `lib/storyarn/localization/text_extractor.ex` lines ~118-260
- **Impact:** For each entity, calls `TextCrud.upsert_text` individually per field/locale combination. A project with 100 nodes, 3 fields each, and 2 target locales = 600 individual INSERT/UPDATE queries
- **Fix:** Batch with `Repo.insert_all` using `on_conflict` option, processing in chunks of 100-500

### Warnings

**W1: `PropertyInheritance.sync_instance_variable_names/3` -- per-sheet queries**
- **File:** `lib/storyarn/sheets/property_inheritance.ex` lines ~511-531
- **Impact:** Issues individual queries per instance sheet when syncing variable names
- **Fix:** Batch update with a single query using `Repo.update_all` with CASE expression

**W2: `PropertyInheritance.cleanup_hidden_block_ids/3` -- load then update individually**
- **File:** `lib/storyarn/sheets/property_inheritance.ex` lines ~542-554
- **Impact:** Loads each sheet then updates individually
- **Fix:** Use `Repo.update_all` with array removal expression

**W3: `MapCrud.restore_children/3` -- sequential updates in recursive restore**
- **File:** `lib/storyarn/maps/map_crud.ex` lines ~363-384
- **Impact:** Issues individual updates when restoring soft-deleted map tree
- **Fix:** Use `Repo.update_all` with `where: id in ^descendant_ids`

**W5: `TableCrud.reorder_columns/3` -- N individual updates**
- **File:** `lib/storyarn/sheets/table_crud.ex` lines ~217-230
- **Impact:** Same pattern as block reordering: one UPDATE per column
- **Fix:** Batch UPDATE with CASE expression

**W6: `TableCrud.restore_column_cell_values/2` -- Repo.get per row**
- **File:** `lib/storyarn/sheets/table_crud.ex` lines ~203-214
- **Impact:** Individual `Repo.get` per table row when restoring column values
- **Fix:** Use `Repo.update_all` with JSONB set expression

**W8: `PropertyInheritance.copy_table_structure_to_instances/3` -- N+1 count pattern**
- **File:** `lib/storyarn/sheets/property_inheritance.ex` lines ~634-651
- **Impact:** Checks table count per instance sheet before copying
- **Fix:** Batch count query grouped by sheet_id

---

## 2. Database Index Analysis

### Missing Indexes

**MI1: `map_layers` -- missing individual `map_id` index**
- **File:** `priv/repo/migrations/20260217140000_create_map_tables.exs`
- **Issue:** Only has composite `[map_id, position]` index. Queries filtering by `map_id` alone cannot use the composite index efficiently
- **Fix:** Add `create index(:map_layers, [:map_id])`

**MI2: `flow_nodes.deleted_at` -- no partial index for active nodes**
- **File:** `priv/repo/migrations/20260201120005_create_flows.exs`
- **Issue:** Nearly every flow_nodes query filters `where is_nil(deleted_at)`, but there is no partial index
- **Fix:** Add `create index(:flow_nodes, [:deleted_at], where: "deleted_at IS NOT NULL", name: :flow_nodes_trash_index)`

**MI3: JSONB expression indexes for `FlowCrud.search_flows_deep`**
- **File:** `lib/storyarn/flows/flow_crud.ex` lines ~146-160
- **Issue:** Searches across 8 JSONB keys using ILIKE without expression indexes — full table scan
- **Fix:** Add GIN trigram index on most-searched fields, or composite GIN index on full `data` column

**MI4: `map_connections` -- missing `from_pin_id` and `to_pin_id` indexes**
- **File:** `priv/repo/migrations/20260217140000_create_map_tables.exs`
- **Issue:** No individual indexes on pin reference columns
- **Fix:** Add `create index(:map_connections, [:from_pin_id])` and `create index(:map_connections, [:to_pin_id])`

### Existing Good Indexes
- Sheets: Comprehensive indexes including composite `[project_id, parent_id, position]`, unique shortcuts, trash index
- Flows: Good composite indexes for tree operations, unique shortcut index
- Projects/Workspaces: Proper membership and invitation indexes

---

## 3. LiveView Socket Assigns

### Critical

**C3: No LiveView streams used in any editor**
- **Files:**
  - `lib/storyarn_web/live/flow_live/show.ex` -- stores `@nodes`, `@connections`, `@all_sheets`, `@flows_tree`, `@project_variables`, `@available_maps`, `@available_flows` all in assigns
  - `lib/storyarn_web/live/sheet_live/show.ex` -- stores `@blocks`, `@children`, `@sheets_tree` in assigns
  - `lib/storyarn_web/live/map_live/show.ex` -- stores full map data, trees, ancestors in assigns
- **Impact:** All list data is held in socket assigns, meaning every item in every list is diff-checked on every render
- **Fix:** Convert `@nodes`, `@blocks`, `@connections` to streams. Use `stream/3` and `stream_insert/3` for incremental updates
- **Note:** Only 2 uses of `temporary_assigns` found across the entire codebase (auth forms and a generic table component)

### Warnings

**W4: `VariableReferenceTracker` -- extra query on every zone/pin save**
- **File:** `lib/storyarn/flows/variable_reference_tracker.ex` line ~72
- **Impact:** Calls `get_map_project_id` adding 1 extra query on every map zone or pin save operation
- **Fix:** Pass `project_id` as parameter from the caller (ZoneCrud/PinCrud already have access to the map)

**W7: MapLive.Show synchronous mount -- loads everything eagerly**
- **File:** `lib/storyarn_web/live/map_live/show.ex` lines ~311-367
- **Impact:** Unlike FlowLive (which uses `start_async` for deferred loading), MapLive loads all data synchronously in mount
- **Fix:** Apply the same `start_async` pattern used in FlowLive.Show for deferred data loading

---

## 4. Query Patterns

### SELECT * Usage
- Most queries use full schema selects without explicit `select:`
- **Notable exceptions (good):** `NodeCrud.list_hubs/1` uses explicit select, `NodeCrud.list_exit_nodes_for_flow/1` uses explicit select
- **Recommendation:** Add explicit selects to list queries that only need a few fields, particularly tree-building queries

### Unbounded Queries
- `SheetQueries.list_project_variables/1` -- loads ALL variables for a project with no LIMIT
- `TextExtractor.extract_all/1` -- loads ALL flows, nodes, sheets, blocks for a project
- `FlowCrud.list_flows/1` -- loads all flows without pagination
- **Mitigation:** Most of these are project-scoped, which provides implicit bounds

---

## 5. JavaScript Bundle Analysis

### Critical: Monolithic Bundle

**File:** `assets/js/app.js` lines ~28-68

All 41 hooks are imported eagerly at the top of `app.js`. Every page load downloads and parses all editor code regardless of which editor the user is viewing. This includes:
- **Rete.js ecosystem** (8 packages): flow editor only
- **Leaflet + plugins** (3 packages): map editor only
- **Tiptap** (6 packages): rich text editing only
- **CodeMirror** (5 packages): expression editor only
- **Other heavy deps:** lit, elkjs, html2canvas, sortablejs

**Fix:** Implement dynamic `import()` for heavy hooks or use Phoenix LiveView's lazy hook loading.

---

## 6. PubSub Patterns

### Good Patterns Observed
- **Proper topic scoping:** `"flow:{flow_id}:changes"`, `"flow:{flow_id}:cursors"` etc.
- **Separate channels:** Presence, changes, locks, and cursors are on separate PubSub topics
- **Self-filtering:** Handlers check `user_id != current_user_id` to skip self-originated events

### Warnings

**W9: `FlowCrud.notify_affected_subflows/2` -- potential broadcast storm**
- **File:** `lib/storyarn/flows/flow_crud.ex` lines ~361-374
- **Impact:** When a flow is deleted, broadcasts `:flow_refresh` to every flow referencing it

**W10: Cursor broadcasting frequency**
- **File:** `lib/storyarn/collaboration.ex`
- **Impact:** Cursor updates broadcast on every mouse move. With 5+ concurrent users, generates substantial PubSub traffic
- **Mitigation:** JS-side likely throttles, but server-side throttling could further reduce load

---

## Positive Patterns Observed

1. **Batch subflow resolution** (`NodeCrud.batch_resolve_subflow_data/1`) -- pre-fetches in 2 queries instead of N+1
2. **Recursive CTE** in `SheetQueries.list_ancestors` -- proper SQL recursion
3. **Window functions** in `MapCrud.list_maps_tree_with_elements` -- `ROW_NUMBER()` with element limit
4. **Deferred async loading** in `FlowLive.Show` -- uses `start_async`
5. **Parameterized JSONB queries** -- proper fragment bindings
6. **Tree building in memory** -- flat query then Elixir tree construction
7. **Soft-delete aware queries** -- consistent `is_nil(deleted_at)` filtering

---

## Optimization Recommendations (Prioritized)

### Priority 1 -- High Impact, Low Effort

1. **Add missing database indexes** (MI1-MI4) -- Estimated effort: 1 hour
2. **Convert `MapCrud.list_ancestors` to recursive CTE** -- Estimated effort: 2 hours
3. **Batch reorder operations** (C2, W5) -- Estimated effort: 3 hours

### Priority 2 -- High Impact, Medium Effort

4. **Implement LiveView streams for node/block/connection lists** (C3) -- Estimated effort: 1-2 days per editor
5. **Apply `start_async` deferred loading to MapLive.Show** (W7) -- Estimated effort: 4 hours
6. **Batch TextExtractor.extract_all upserts** (C4) -- Estimated effort: 4 hours

### Priority 3 -- Medium Impact, Higher Effort

7. **Implement JS code splitting** -- Estimated effort: 1 day
8. **Batch PropertyInheritance operations** (W1, W2, W8) -- Estimated effort: 1 day

### Priority 4 -- Low Impact, Low Effort

9. **Pass `project_id` to VariableReferenceTracker** (W4) -- Estimated effort: 30 minutes
10. **Add explicit selects to list queries** -- Estimated effort: 2 hours

---

## Score Breakdown

| Area                   | Score  | Max     | Notes                                            |
|------------------------|--------|---------|--------------------------------------------------|
| N+1 Query Prevention   | 14     | 25      | Good batch patterns exist but several N+1 remain |
| Database Indexes       | 16     | 20      | Mostly good, 4 missing                           |
| LiveView Memory        | 8      | 20      | No streams, no temporary_assigns in editors      |
| Query Efficiency       | 15     | 15      | Good parameterization, proper CTEs               |
| JavaScript Bundle      | 7      | 10      | Monolithic but deps are appropriate for features |
| PubSub Patterns        | 12     | 10      | Excellent topic scoping (+2 bonus)               |
| **Total**              | **72** | **100** |                                                  |
