# Coverage 80% Plan — From 64.46% to 80%+

## Strategy

Gap: 15.5pp (~4,000-5,500 executable lines needed)
Approach: Pure functions first, then domain modules, then LiveView handlers.

---

## Phase 1: Pure Function Tests (no DB, no LiveView)

- [ ] [P1-T1] Player.Slide unit tests (222 lines, 0% → ~80%)
  - File: `test/storyarn_web/live/flow_live/player/slide_test.exs`
  - Source: `lib/storyarn_web/live/flow_live/player/slide.ex`
  - Test: All public functions — build_slide/2, format helpers, edge cases

- [ ] [P1-T2] Player.PlayerEngine unit tests (91 lines, 0% → ~80%)
  - File: `test/storyarn_web/live/flow_live/player/player_engine_test.exs`
  - Source: `lib/storyarn_web/live/flow_live/player/player_engine.ex`
  - Test: init, step, choose_response, step_back, state transitions

- [ ] [P1-T3] SheetLive.Helpers.BlockHelpers unit tests (300 lines, 0% → ~70%)
  - File: `test/storyarn_web/live/sheet_live/helpers/block_helpers_test.exs`
  - Source: `lib/storyarn_web/live/sheet_live/helpers/block_helpers.ex`
  - Test: Pure helper functions that don't touch socket/DB

- [ ] [P1-T4] SheetLive.Helpers.ConfigHelpers unit tests (265 lines, 0% → ~70%)
  - File: `test/storyarn_web/live/sheet_live/helpers/config_helpers_test.exs`
  - Source: `lib/storyarn_web/live/sheet_live/helpers/config_helpers.ex`
  - Test: Config computation helpers

- [ ] [P1-T5] SheetLive.Helpers.BlockValueHelpers unit tests (202 lines, 0% → ~70%)
  - File: `test/storyarn_web/live/sheet_live/helpers/block_value_helpers_test.exs`
  - Source: `lib/storyarn_web/live/sheet_live/helpers/block_value_helpers.ex`
  - Test: Value coercion, default values, type conversions

---

## Phase 2: Domain Module Tests (DataCase, need DB)

- [ ] [P2-T1] Flows.NodeCrud expanded tests (423 lines, 40% → ~75%)
  - File: `test/storyarn/flows/node_crud_test.exs` (new or expand)
  - Source: `lib/storyarn/flows/node_crud.ex`
  - Test: Create/update/delete for all 9 node types, edge cases, error paths

- [ ] [P2-T2] Sheets.SheetQueries expanded tests (1159 lines, 68% → ~85%)
  - File: `test/storyarn/sheets/sheet_queries_test.exs` (new or expand)
  - Source: `lib/storyarn/sheets/sheet_queries.ex`
  - Test: Query functions, filters, search, preloads, edge cases

- [ ] [P2-T3] Scenes.SceneCrud expanded tests (928 lines, 68% → ~85%)
  - File: `test/storyarn/scenes/scene_crud_test.exs` (new or expand)
  - Source: `lib/storyarn/scenes/scene_crud.ex`
  - Test: CRUD operations, tree manipulation, soft delete

- [ ] [P2-T4] Localization.TextExtractor expanded tests (519 lines, 54% → ~80%)
  - File: `test/storyarn/localization/text_extractor_test.exs` (new or expand)
  - Source: `lib/storyarn/localization/text_extractor.ex`
  - Test: Extract from dialogue/condition/instruction nodes, edge cases

---

## Phase 3: LiveView Handler Tests (ConnCase)

- [ ] [P3-T1] SettingsLive.WorkspaceMembers tests (318 lines, 0% → ~60%)
  - File: `test/storyarn_web/live/settings_live/workspace_members_test.exs`
  - Test: mount, list members, role changes, invitations

- [ ] [P3-T2] SettingsLive.WorkspaceGeneral tests (194 lines, 0% → ~60%)
  - File: `test/storyarn_web/live/settings_live/workspace_general_test.exs`
  - Test: mount, form render, update workspace settings

- [ ] [P3-T3] SheetLive.Handlers.UndoRedoHandlers (839 lines, 18% → ~50%)
  - Test via SheetLive.Show integration tests
  - Test: undo/redo state transitions, stack operations

- [ ] [P3-T4] SheetLive.Handlers.TableHandlers (817 lines, 42% → ~65%)
  - Test via SheetLive.Show integration tests
  - Test: add/remove row/column, reorder, cell editing

- [ ] [P3-T5] ExportImportLive.Index expanded (855 lines, 47% → ~70%)
  - File: `test/storyarn_web/live/export_import_live/index_test.exs` (expand)
  - Test: Format selection, export trigger, import flow

---

## Verification

After each phase:
1. `mix test` (full suite)
2. `mix test --cover` (check progress)
3. Target checkpoints: P1 → ~70%, P2 → ~75%, P3 → ~80%
