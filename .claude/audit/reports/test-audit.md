# Test Health Audit Report

**Project:** Storyarn
**Date:** 2026-02-23
**Score: 72 / 100**

---

## Executive Summary

Storyarn has a solid and well-structured test suite with **2,318 tests, 0 failures, and 43 excluded (E2E)** across **91 test files**. Domain contexts are well-covered with behavior-focused tests, and the LiveView tests for Map and Screenplay editors are exceptionally thorough. However, significant gaps exist: the entire `shared/` utility library (10 modules) has zero dedicated tests, 12 LiveViews have no test coverage at all, nearly all DataCase tests run synchronously (missing `async: true`), and there are no tests for the player system that renders flows.

---

## 1. Test Coverage Assessment

### 1.1 Source vs Test File Counts

| Area                      | Source Files  | Test Files  | Ratio   |
|---------------------------|---------------|-------------|---------|
| `lib/storyarn/` (domain)  | 161           | 62          | 38%     |
| `lib/storyarn_web/` (web) | 179           | 29          | 16%     |
| **Total**                 | **340**       | **91**      | **27%** |

### 1.2 Domain Context Coverage

| Context       | Source Modules  | Test Files  | Coverage         |
|---------------|-----------------|-------------|------------------|
| Accounts      | 14              | 1           | Good             |
| Assets        | 5               | 2           | Good             |
| Authorization | 1               | 1           | Excellent        |
| Collaboration | 4               | 1           | Good             |
| Flows         | 20              | 9           | Strong           |
| Localization  | 15              | 7           | Good             |
| Maps          | 13              | 1           | Adequate         |
| Projects      | 7               | 1           | Good             |
| Screenplays   | 18              | 18          | Excellent        |
| Sheets        | 14              | 8           | Good             |
| **Shared**    | **10**          | **0**       | **CRITICAL GAP** |
| Workspaces    | 7               | 1           | Good             |

### 1.3 LiveView Coverage

**Well-tested:**
- Map editor: 3,441-line test file with 51 describe blocks, IDOR tests, 19 viewer rejection tests
- Screenplay editor: 2,213-line test file
- Flow editor: 7 test files covering events, collaboration, debug, navigation
- User auth: 4 test files

**Completely untested (12 LiveViews):**
- `lib/storyarn_web/live/localization_live/` (3 files: index, edit, report)
- `lib/storyarn_web/live/settings_live/` (5 files: profile, security, connections, workspace_general, workspace_members)
- `lib/storyarn_web/live/workspace_live/` (4 files: index, show, invitation, new)
- `lib/storyarn_web/live/flow_live/player_live.ex` (+ 5 player component files)
- `lib/storyarn_web/live/map_live/exploration_live.ex`

### 1.4 Untested Shared Utilities (10 modules, HIGH PRIORITY)

All 10 modules in `lib/storyarn/shared/`:
- `name_normalizer.ex` -- Slug/variable/shortcut generation with Unicode transliteration
- `tree_operations.ex` -- Tree reorder/move/cycle detection
- `shortcut_helpers.ex` -- Shortcut lifecycle with backlink protection
- `soft_delete.ex` -- Recursive soft-delete
- `validations.ex` -- Shortcut/email format regex validators
- `map_utils.ex` -- Key conversion utilities
- `search_helpers.ex` -- SQL LIKE injection prevention
- `time_helpers.ex` -- Timestamp truncation
- `token_generator.ex` -- Crypto token generation
- `encrypted_binary.ex` -- Ecto encrypted type

---

## 2. Test Quality -- GOOD

**Behavior-focused:** Tests use public context API, not internal implementation. Example: tests call `Flows.create_flow/2`, not `FlowCrud.create_flow/2`.

**Assertion patterns:** Good use of pattern matching (`assert {:ok, "owner", :project} = ...`), proper `refute` usage (269 occurrences across 50 files), and `errors_on/1` for changeset validation.

**Mocking:** Mox infrastructure exists but is unused. All tests use real database -- no over-mocking.

**Fixtures:** Well-organized in `test/support/fixtures/` (9 files). Use `System.unique_integer` for uniqueness. Delegate to production context functions. No raw `Repo.insert!` calls.

---

## 3. Test Organization -- GOOD

Clean structure:
- `test/support/` with DataCase, ConnCase, Factory, Mocks, and 9 fixture modules
- No test helper duplication observed
- E2E tests properly separated with `@moduletag :e2e` and excluded by default
- ExMachina factory properly initialized in `test_helper.exs`

**Large file concern:** `map_live/show_test.exs` (3,441 lines) could benefit from splitting, similar to how flow_live splits into show_events, collaboration, debug handler test files.

---

## 4. LiveView Test Patterns -- GOOD WHERE PRESENT

LiveView tests properly:
- Authenticate with `register_and_log_in_user` setup
- Navigate real routes with `live(conn, path)`
- Test events with `render_click`, `render_hook`, `render_async`
- Verify both HTML and database state
- Test viewer authorization by creating viewer memberships

**Sheet LiveView tests are thin** (216 lines in `show_test.exs`). Block CRUD, config panel, table operations, undo/redo are untested at the LiveView level.

---

## 5. Flaky Test Risk -- LOW

- **Zero** `Process.sleep` or `:timer.sleep` in test files
- No external HTTP calls in tests
- `Locks.clear_all()` in setup for shared ETS state
- `debug_session_store_test.exs` correctly uses `async: false`
- SQL Sandbox properly configured

---

## 6. Async Usage -- NEEDS IMPROVEMENT

| Category         | async: true   | sync  | Total  |
|------------------|---------------|-------|--------|
| DataCase         | **1**         | 29    | 30     |
| ConnCase (async) | 10            | 16    | 26     |
| ExUnit.Case      | 11            | 0     | 11     |

Only 1 out of 30 DataCase tests uses `async: true`. Since PostgreSQL supports async sandbox, most could safely run async. The test suite takes 23-25 seconds; enabling async could reduce this by 30-50%.

---

## 7. Missing Critical Tests

1. **Shared utilities** (10 modules, 0 tests) -- affects every context
2. **Player system** (6 files, 0 tests) -- user-facing feature
3. **12 LiveViews** with zero coverage (settings, workspace, localization)
4. **Concurrent operations** -- no race condition tests
5. **Rate limiter** (`lib/storyarn/rate_limiter.ex`) -- untested
6. **Database constraint violations** -- unique index conflict handling untested
7. **Unicode edge cases** in NameNormalizer -- CJK, RTL, emoji
8. **Sheet LiveView** -- only 216 lines, missing block CRUD, table, undo/redo events

---

## 8. Recommendations (Priority Order)

### P1: Add Shared Utilities Tests (HIGH impact, LOW effort)
Create `test/storyarn/shared/` with tests for all 10 modules. These are pure functions, easy to test with `async: true`.

### P2: Enable async: true on DataCase tests (MEDIUM impact, LOW effort)
Add `async: true` to 29 synchronous DataCase test files. Could cut suite time 30-50%.

### P3: Test Missing LiveViews (MEDIUM impact, MEDIUM effort)
Add tests for settings_live, workspace_live, localization_live, and player_live.

### P4: Expand Sheet LiveView Tests (MEDIUM impact, MEDIUM effort)
Add block CRUD, config panel, table operation, undo/redo tests.

### P5: Split Large Test Files (LOW impact, LOW effort)
Split `map_live/show_test.exs` (3,441 lines) into per-handler files.

---

## Score Justification: 72/100

| Category                 | Score  | Max  |
|--------------------------|--------|------|
| Context coverage         | 17     | 20   |
| LiveView coverage        | 10     | 20   |
| Shared utilities         | 0      | 10   |
| Test quality             | 15     | 15   |
| Test organization        | 10     | 10   |
| Authorization testing    | 8      | 10   |
| Edge cases / error paths | 5      | 10   |
| Performance (async)      | 3      | 5    |
| Flaky test risk          | 5      | 5    |
