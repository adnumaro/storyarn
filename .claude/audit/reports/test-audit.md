# Test Health Audit

## Score: 82/100

**Test run result:** 2307 tests, 0 failures (43 excluded E2E), completed in 24.0 seconds

## Test Inventory

- **Total test files:** 91 (58 domain + 29 web + 4 E2E)
- **Total test cases:** ~2307
- **Async test files:** 42

### By Context

| Context       | Files  | Tests  | Notes                                                     |
|---------------|--------|--------|-----------------------------------------------------------|
| flows         | 12     | 439    | Largest — evaluator, conditions, instructions, references |
| screenplays   | 21     | 491    | Most test files                                           |
| sheets        | 10     | 332    | Constraints, inheritance, versioning, tables              |
| maps          | 1      | 107    | CRUD, pins, zones, layers                                 |
| localization  | 7      | 92     | Good sub-module coverage                                  |
| accounts      | 1      | 59     | Auth testing                                              |
| assets        | 2      | 45     | Image processing                                          |
| projects      | 1      | 37     | CRUD, memberships                                         |
| workspaces    | 1      | 25     | Basic CRUD                                                |
| authorization | 1      | 16     | Roles, permissions                                        |
| collaboration | 1      | 19     | Colors, locks                                             |

### LiveView Tests

| Area            | Files   | Tests   |
|-----------------|---------|---------|
| map_live        | 2       | 192     |
| flow_live       | 6       | 120     |
| screenplay_live | 2       | 109     |
| components      | 2       | 47      |
| user_live       | 4       | 35      |
| asset_live      | 1       | 29      |
| user_auth       | 1       | 27      |
| sheet_live      | 3       | 22      |
| project_live    | 3       | 21      |
| controllers     | 5       | 19      |

## Findings

### Critical

1. **No tests for `localization_live/`** — zero test files for the localization LiveView
2. **No tests for `settings_live/`** — zero test files for settings pages
3. **No tests for `workspace_live/`** — zero test files for workspace management
4. **`Process.sleep(1100)` in sheets_test.exs:935** — flaky test indicator depending on timestamp ordering

### Warnings

- `:timer.sleep(10)` in projects_fixtures.ex:104 — race condition in email token extraction
- Only 22 tests for `sheet_live/` — thin for a major editor feature
- Only 2 E2E tests for collaboration
- Empty `test/support/mocks.ex` — no mock definitions
- 132 LiveView source files vs 21 test files (1:6 ratio)
- `project_live/invitation_test.exs` has only 6 tests

### Good Patterns

- Zero test failures across 2307 tests
- 581 describe blocks showing strong organization
- 9 well-structured fixture modules + ExMachina factory
- Systematic authorization testing for all role combinations
- Pure function testing for evaluator (async, no DB)
- Thorough edge case coverage (nil conditions, empty rules, invalid structures)
- LiveView tests exercise real events with `render_click`, `render_hook`
- E2E with Playwright, properly excluded from default run
- 42 async files for parallel execution
- Specific assertions throughout

## Coverage Gaps

| Area                   | Status          |
|------------------------|-----------------|
| `localization_live/`   | **No tests**    |
| `settings_live/`       | **No tests**    |
| `workspace_live/`      | **No tests**    |
| `sheet_live/`          | Thin (22 tests) |
| `Storyarn.Mailer`      | No tests        |
| `Storyarn.Vault`       | No tests        |
| `Storyarn.RateLimiter` | No tests        |
| `Storyarn.Shortcuts`   | No direct tests |
