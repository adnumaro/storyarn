# Project Health Audit: Storyarn

**Generated**: 2026-02-22
**Mode**: Full audit (5 parallel specialists)
**Stack**: Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL
**Codebase**: 339 Elixir files (67K LOC) + 23K JS LOC + 91 test files (38K LOC)

---

## Executive Summary

### Health Score: C+ (76/100)

| Category     | Score   | Status          |
|--------------|---------|-----------------|
| Test Quality | 82/100  | Good            |
| Architecture | 78/100  | Good            |
| Security     | 78/100  | Needs Attention |
| Performance  | 72/100  | Needs Attention |
| Dependencies | 72/100  | Needs Attention |

### Critical Issues (Must Address)

1. **[SECURITY] HTML Sanitizer XSS bypass** — `unsafe_attr?/2` logic bug allows `<a href="javascript:...">` through sanitization. Combined with `raw()` usage in player/localization views, this is exploitable. (`html_sanitizer.ex:36-45`)

2. **[SECURITY] Missing authorization in 6+ LiveView event handlers** — `sheet_title`, `sheet_avatar`, `banner`, `undo_redo` components check permissions only at UI level. Crafted WebSocket events bypass the restriction.

3. **[ARCHITECTURE] Repo leaks into LiveView layer** — 28 LiveView files with 50+ direct `Repo` calls (preload, get_by, insert). Breaks context boundary contract.

4. **[PERFORMANCE] Recursive N+1 in tree operations** — `get_descendant_sheet_ids`, `build_ancestor_list`, `preload_children_recursive` fire O(N) queries for tree traversal. Should use recursive CTEs.

5. **[PERFORMANCE] N+1 in table cell mutations** — `add_cell_to_all_rows`, `remove_cell_from_all_rows` update rows individually. With inheritance: 50 sheets x 20 rows = 1000+ updates.

### Cross-Category Correlations

- **Repo leaks ↔ Authorization gaps**: The LiveView components that bypass auth (`sheet_title`, `sheet_avatar`, `banner`) are the same ones making direct Repo calls. Fixing the Repo leak by routing through contexts would naturally add an authorization enforcement point.

- **Sheets ↔ Flows coupling ↔ Performance**: The bidirectional coupling between Sheets and Flows contexts (referenced by both Architecture and Performance auditors) means performance fixes to tree traversal will need coordination across both contexts.

- **Sanitizer bug ↔ raw() usage ↔ Test gaps**: The XSS vulnerability exists because (a) the sanitizer has a bug, (b) `raw()` is used on user content, and (c) there are zero tests for `localization_live/` where one of the `raw()` calls lives.

---

## Detailed Findings by Priority

### Tier 1: Fix Now (Security + Data Integrity)

| #   | Category   | Finding                                                                                | Effort   |
|-----|------------|----------------------------------------------------------------------------------------|----------|
| 1   | Security   | Fix `unsafe_attr?/2` to check `javascript:` in href values                             | 30 min   |
| 2   | Security   | Add `with_edit_authorization` to sheet_title, sheet_avatar, banner, undo_redo handlers | 2 hrs    |
| 3   | Security   | Sanitize `raw()` content in localization editor                                        | 30 min   |
| 4   | Security   | Enable `force_ssl` and `secure: true` on session cookies for production                | 30 min   |
| 5   | Security   | Add `filter_parameters` config for log scrubbing                                       | 15 min   |

### Tier 2: Fix Soon (Performance + Architecture)

| #   | Category     | Finding                                                                      | Effort   |
|-----|--------------|------------------------------------------------------------------------------|----------|
| 6   | Performance  | Replace recursive `get_descendant_sheet_ids` with CTE                        | 1 day    |
| 7   | Performance  | Replace `preload_children_recursive` with single-query tree build            | 1 day    |
| 8   | Performance  | Batch table row cell operations with JSONB `Repo.update_all`                 | 1 day    |
| 9   | Architecture | Eliminate Repo from LiveView components (28 files, 50+ calls)                | 2-3 days |
| 10  | Performance  | Replace individual `Repo.insert` loops in ReferenceTracker with `insert_all` | 2 hrs    |
| 11  | Performance  | Consolidate `progress_by_language` into single GROUP BY query                | 1 hr     |

### Tier 3: Improve (Quality + Maintenance)

| #   | Category     | Finding                                                                 | Effort   |
|-----|--------------|-------------------------------------------------------------------------|----------|
| 12  | Architecture | Decouple Sheets ↔ Flows bidirectional dependency                        | 3-5 days |
| 13  | Architecture | Extract Shortcuts queries into per-context functions                    | 1 day    |
| 14  | Tests        | Add tests for `localization_live/`, `settings_live/`, `workspace_live/` | 2-3 days |
| 15  | Tests        | Fix `Process.sleep(1100)` flaky test in sheets_test.exs                 | 1 hr     |
| 16  | Dependencies | Remove unused JS packages: `leaflet-textpath`, `rete-render-utils`      | 15 min   |
| 17  | Dependencies | Move `@lezer/lr` from devDependencies to dependencies                   | 5 min    |
| 18  | Dependencies | Pin `postgrex` constraint to `~> 0.22`                                  | 5 min    |

### Tier 4: Backlog (Nice to Have)

| #   | Category     | Finding                                                | Effort   |
|-----|--------------|--------------------------------------------------------|----------|
| 19  | Architecture | Break Flows internal 7-module dependency cycle         | 2 days   |
| 20  | Architecture | Reduce FlowLive.Show event routing table (84+ clauses) | 1 day    |
| 21  | Dependencies | Migrate `ex_aws` from `hackney` to `Req`/`Finch`       | 1-2 days |
| 22  | Dependencies | Replace `html_sanitize_ex` (abandoned since 2021)      | 1 day    |
| 23  | Dependencies | Evaluate `hammer` 7.x upgrade                          | 1 day    |
| 24  | Tests        | Add property-based tests for constraint validators     | 1-2 days |
| 25  | Performance  | Replace `build_ancestor_list` with recursive CTE       | 2 hrs    |

---

## Strengths

The codebase has several strong architectural patterns worth preserving:

1. **2307 passing tests, 0 failures** — Suite is healthy and fast (24s)
2. **Consistent facade + defdelegate pattern** across all 8 contexts
3. **Per-node-type architecture** — 2 files per node type, mirrored in JS
4. **Strong authentication** — Bcrypt, Cloak encryption, rate limiting, session management
5. **Good database indexing** — Composite, partial unique, FK indexes throughout
6. **Clean Collaboration context** — Fully self-contained, PubSub-only communication
7. **Handler decomposition** — Events consistently routed to focused handler modules
8. **Strong type specifications** — `@spec` on virtually all public facade functions
9. **Modern JS tooling** — Biome, Vitest, Playwright, coherent library ecosystems

---

## Action Plan

### Immediate (This Sprint)
- [ ] Fix HTML sanitizer `unsafe_attr?/2` bug (XSS)
- [ ] Add authorization to 6 unprotected LiveView event handlers
- [ ] Sanitize `raw()` content in localization editor
- [ ] Enable `force_ssl` + `secure` cookie flag
- [ ] Add `filter_parameters` config

### Short-term (Next 2 Sprints)
- [ ] Replace recursive tree queries with CTEs (3 locations)
- [ ] Batch table cell mutations with JSONB operators
- [ ] Start Repo elimination from LiveView layer (prioritize components with auth gaps)
- [ ] Add tests for 3 untested LiveView directories

### Long-term (Backlog)
- [ ] Decouple Sheets ↔ Flows bidirectional dependency
- [ ] Migrate from `hackney` to `Req`/`Finch`
- [ ] Replace abandoned `html_sanitize_ex`
- [ ] Break internal dependency cycles

---

## Reports

- [Architecture Review](reports/arch-review.md)
- [Performance Audit](reports/perf-audit.md)
- [Security Audit](reports/security-audit.md)
- [Test Health Audit](reports/test-audit.md)
- [Dependency Audit](reports/deps-audit.md)
