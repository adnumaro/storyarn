# Cross-Context Deduplication Refactor Plan

## Phase 1 — Quick wins (alto impacto, bajo esfuerzo)

### 1.1 `Storyarn.Shared.ImportHelpers` [~2h]
**Create** `lib/storyarn/shared/import_helpers.ex` with:
- `detect_shortcut_conflicts(schema, project_id, shortcuts)` — generic version
- `soft_delete_by_shortcut(schema, project_id, shortcut)` — generic version
- `bulk_insert(schema, attrs_list, chunk_size \\ 500)` — generic chunked insert

**Modify** (remove duplicates, delegate to ImportHelpers):
- `lib/storyarn/flows/flow_crud.ex` — lines 627-664
- `lib/storyarn/scenes/scene_crud.ex` — lines 812-848
- `lib/storyarn/screenplays/screenplay_crud.ex` — lines 265-276, 338-350

**Modify facades** to expose via defdelegate:
- `lib/storyarn/flows.ex`
- `lib/storyarn/scenes.ex`
- `lib/storyarn/screenplays.ex`

### 1.2 `TreeOperations.build_tree_from_flat_list/1` [~1h]
**Modify** `lib/storyarn/shared/tree_operations.ex` — add:
- `build_tree_from_flat_list(items)` — generic in-memory tree builder

**Modify** (replace inline tree building):
- `lib/storyarn/flows/flow_crud.ex` — lines 32-55 (remove `build_tree/2`, `build_subtree/2`)
- `lib/storyarn/scenes/scene_crud.ex` — lines 34-50 (remove `build_tree/1`, `build_subtree/2`)
- `lib/storyarn/screenplays/screenplay_crud.ex` — lines 32-56 (remove `build_tree/2`, `build_subtree/2`)

### 1.3 `assets/js/utils/event_dispatcher.js` [~1h]
**Create** `assets/js/utils/event_dispatcher.js` with:
- `pushWithTarget(hook, eventName, payload)` — target-aware push

**Modify** highest-impact hooks first (20+ files, but mechanical replacement):
- All hooks that use the `if target pushEventTo else pushEvent` pattern

### 1.4 `SaveStatusTimer.mark_saved/1` [~30min]
**Modify** `lib/storyarn_web/helpers/save_status_timer.ex` — add:
- `mark_saved(socket)` — combines `assign(:save_status, :saved) |> schedule_reset()`

**Modify** callers:
- `lib/storyarn_web/live/sheet_live/show.ex` (~6 call sites)
- `lib/storyarn_web/live/flow_live/show.ex` (~4 call sites)

---

## Phase 2 — Medio esfuerzo, alto impacto

### 2.1 `Storyarn.Shared.HierarchicalSchema` [~3h]
**Create** `lib/storyarn/shared/hierarchical_schema.ex` with:
- `delete_changeset(entity)` — sets `deleted_at`
- `restore_changeset(entity)` — clears `deleted_at`
- `move_changeset(entity, attrs)` — casts `parent_id` + `position`
- `deleted?(entity)` — checks `deleted_at`
- `validate_core_fields(changeset)` — name required, 1-200 chars
- `validate_description(changeset)` — max 2000 chars

**Modify** schemas (delegate to shared):
- `lib/storyarn/sheets/sheet.ex`
- `lib/storyarn/flows/flow.ex`
- `lib/storyarn/scenes/scene.ex`
- `lib/storyarn/screenplays/screenplay.ex`

### 2.2 `<.entity_tree_section>` component [~4h]
**Create** generic tree section in `lib/storyarn_web/components/entity_tree.ex` with slots:
- `:item_component` — custom rendering per domain
- `:menu_items` — domain-specific menu options
- Props: `entity_type`, `items_tree`, `selected_id`, `can_edit`, etc.

**Modify** sidebar trees (simplify to use generic component):
- `lib/storyarn_web/components/sidebar/sheet_tree.ex`
- `lib/storyarn_web/components/sidebar/flow_tree.ex`
- `lib/storyarn_web/components/sidebar/scene_tree.ex`
- `lib/storyarn_web/components/sidebar/screenplay_tree.ex`

### 2.3 `assets/js/utils/file_upload_handler.js` [~2h]
**Create** shared upload utility with:
- `setupFileUpload(hook, config)` — type validation, size validation, base64 reading

**Modify** upload hooks (reduce to config-only):
- `assets/js/hooks/asset_upload.js`
- `assets/js/hooks/audio_upload.js`
- `assets/js/hooks/avatar_upload.js`
- `assets/js/hooks/banner_upload.js`

### 2.4 `assets/js/utils/contenteditable_editor.js` [~2h]
**Create** shared inline editing utility with:
- `setupEditableElement(hook, config)` — key handling, debounce, sanitize, save

**Modify** editable hooks:
- `assets/js/hooks/editable_title.js`
- `assets/js/hooks/editable_shortcut.js`
- `assets/js/hooks/editable_block_label.js`

---

## Phase 3 — Refactoring profundo

### 3.1 `Storyarn.Shared.QueryBuilders` [~4h]
**Create** `lib/storyarn/shared/query_builders.ex` with:
- `base_project_query(schema, project_id)` — soft-delete filtered
- `search_query(schema, project_id, term, opts)` — ILIKE name + shortcut
- `tree_query(schema, project_id, opts)` — ordered for tree building
- `get_query(schema, project_id, id, preloads)` — get by project + id

**Modify** query/CRUD modules:
- `lib/storyarn/sheets/sheet_queries.ex`
- `lib/storyarn/flows/flow_crud.ex`
- `lib/storyarn/scenes/scene_crud.ex`
- `lib/storyarn/screenplays/screenplay_crud.ex`

### 3.2 Shared LiveView handler patterns [~3h]
**Create** `lib/storyarn_web/live/shared/undo_redo_dispatcher.ex` with:
- `dispatch_undo(socket, reload_fn, action_handler)`
- `dispatch_redo(socket, reload_fn, action_handler)`

**Create** `lib/storyarn_web/live/shared/generic_entity_handlers.ex` with:
- `handle_set_pending_delete(socket, key, id)`
- `handle_confirm_delete(socket, key, delete_fn)`
- `handle_create_entity(socket, context, attrs, navigate_fn)`

**Modify** handler files:
- `lib/storyarn_web/live/sheet_live/handlers/undo_redo_handlers.ex`
- `lib/storyarn_web/live/scene_live/handlers/undo_redo_handlers.ex`
- All tree_handlers across 4 domains

### 3.3 JS utility consolidation [~4h]
**Create** utilities:
- `assets/js/utils/drag_resize_handler.js` — consolidate 2 resize hooks
- `assets/js/utils/sortable_setup.js` — consolidate 3 sortable hooks
- `assets/js/utils/popover_helpers.js` — template cloning + search filter + event re-pushing
- `assets/js/utils/dom_helpers.js` — `parseDataParams()`, HTML escape

**Modify** affected hooks (10+ files)

---

## Verification per task

Each task MUST:
1. `mix compile --warnings-as-errors` — no warnings
2. `mix test` — all tests pass (no removed tests)
3. `mix format` — formatted
4. Verify affected facades still expose the same public API
