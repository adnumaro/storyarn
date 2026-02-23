# Tier 3: Architecture Repo Leaks + Test Gaps

## Context

Architecture audit (score 78/100) found 50+ direct `Repo` calls in 28 LiveView files. Test audit (score 82/100) found 3 LiveView areas with zero tests and a flaky `Process.sleep` test.

## Phase 1: `get_project_by_slugs` workspace preload (15 files, 1 change)

**Root cause:** `get_project_by_slugs/3` returns project without `:workspace`, forcing every mount to call `Repo.preload(project, :workspace)`.

**Fix:** Add `preload: [:workspace]` to the query in `ProjectCrud.get_project_by_slugs/3`. Then remove all 15 `Repo.preload(project, :workspace)` calls from LiveView mounts.

**Files to update:**
- `lib/storyarn/projects/project_crud.ex` — add preload
- 15 LiveView files — remove `Repo.preload(project, :workspace)` line + remove unused `alias Storyarn.Repo` if no other Repo calls remain

- [ ] P1.1: Add `:workspace` preload to `get_project_by_slugs/3`
- [ ] P1.2: Remove all 15 `Repo.preload(project, :workspace)` in LiveView mounts
- [ ] P1.3: Remove unused `alias Storyarn.Repo` where no other Repo calls remain
- [ ] P1.4: Verify: `mix test`

## Phase 2: Localization ProviderConfig facade (3 files)

**Root cause:** No facade functions for `ProviderConfig` CRUD.

**Fix:** Add `get_provider_config/2` and `upsert_provider_config/3` to `Localization` facade. Update 3 callers.

- [ ] P2.1: Add `get_provider_config/2` and `upsert_provider_config/3` to Localization context
- [ ] P2.2: Update `settings_components.ex` — remove all direct Repo/schema access
- [ ] P2.3: Update `localization_live/edit.ex` — use facade
- [ ] P2.4: Update `localization_helpers.ex` — use facade
- [ ] P2.5: Verify: `mix test`

## Phase 3: Remove redundant Repo.preload before create_version (5 calls)

**Root cause:** `Versioning.create_version/3` already calls `Repo.preload(sheet, :blocks)` internally. Callers preload `:blocks` before passing the sheet — a no-op.

- [ ] P3.1: Remove redundant preloads in `block_helpers.ex` (2 calls)
- [ ] P3.2: Remove redundant preload in `versions_section.ex` (1 call)
- [ ] P3.3: Remove redundant preload in `sheet_title.ex` (1 call)
- [ ] P3.4: Remove redundant preload in `sheet_tree_helpers.ex` (1 call)
- [ ] P3.5: Verify: `mix test`

## Phase 4: Sheet `get_sheet_full/2` facade function (10+ preload calls)

**Root cause:** After update/version operations, LiveViews call `Repo.preload(sheet, [:avatar_asset, :banner_asset, :blocks, :current_version])`. No single facade function returns a "fully loaded" sheet.

**Fix:** Add `Sheets.get_sheet_full/2` returning sheet with all associations. Update callers.

- [ ] P4.1: Add `get_sheet_full/2` to SheetQueries + facade
- [ ] P4.2: Update `versions_section.ex` — use `get_sheet_full`
- [ ] P4.3: Update `sheet_live/show.ex` — use `get_sheet_full`
- [ ] P4.4: Update `sheet_avatar.ex` and `banner.ex` — use `get_sheet_full`
- [ ] P4.5: Update `sheet_title.ex` — use `get_sheet_full`
- [ ] P4.6: Verify: `mix test`

## Phase 5: Propagation modal — use existing context functions (2 calls)

**Root cause:** `propagation_modal.ex` queries Sheet schema directly instead of using Sheets context.

**Fix:** Replace with existing `Sheets.get_children/1` and `Sheets.get_sheet_with_descendants/2`.

- [ ] P5.1: Replace `get_flat_descendants/1` with `Sheets.get_descendant_sheet_ids/1` + `Sheets.list_all_sheets/1`
- [ ] P5.2: Replace `get_descendant_tree/1` with `Sheets.get_sheet_with_descendants/2`
- [ ] P5.3: Remove `import Ecto.Query` and `alias Storyarn.Repo` from propagation_modal
- [ ] P5.4: Verify: `mix test`

## Phase 6: Flow node count_*_in_flow — use socket assigns (3 files)

**Root cause:** `dialogue/node.ex`, `exit/node.ex`, `scene/node.ex` call `Repo.preload(flow, :nodes)` to count nodes. The flow editor already has nodes in socket assigns.

**Fix:** Pass `nodes` list from socket assigns instead of preloading flow.

- [ ] P6.1: Update `dialogue/node.ex` — accept nodes list, remove Repo.preload
- [ ] P6.2: Update `exit/node.ex` — accept nodes list, remove Repo.preload
- [ ] P6.3: Update `scene/node.ex` — accept nodes list, remove Repo.preload
- [ ] P6.4: Update callers to pass `socket.assigns.nodes`
- [ ] P6.5: Verify: `mix test`

## Phase 7: Fix flaky Process.sleep test

**Root cause:** `sheets_test.exs:935` uses `Process.sleep(1100)` to ensure different `deleted_at` timestamps.

**Fix:** Explicitly set `deleted_at` timestamps in the test instead of sleeping.

- [ ] P7.1: Replace `Process.sleep(1100)` with explicit timestamps in assertions
- [ ] P7.2: Verify: `mix test test/storyarn/sheets_test.exs`

## Phase 8: Reference helpers — use facade for block preload (1 call)

**Fix:** Add preload option to `Sheets.list_blocks/1` or use existing `get_sheet_blocks_grouped/1`.

- [ ] P8.1: Update `reference_helpers.ex` to avoid direct `Repo.preload`
- [ ] P8.2: Verify: `mix test`

## Final Verification

- [ ] `mix compile --warnings-as-errors`
- [ ] `mix format --check-formatted`
- [ ] `mix credo --strict`
- [ ] `mix test`
