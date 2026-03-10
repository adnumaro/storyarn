# Plan 3: Sheets Dashboard

**Page:** `/workspaces/:ws/projects/:proj/sheets` (`SheetLive.Index`)
**Current state:** Grid of root sheet cards showing name + children count
**Goal:** Dashboard showing variable system health, sheet completeness, and usage across flows.
**Depends on:** Plan 1 (shared `DashboardComponents`), Plan 2 (may reuse flow-variable cross-reference queries)

---

## CRITICAL: Code Hygiene Rules

### Reuse from Plans 1 & 2
- **`DashboardComponents`** — `stat_card`, `ranked_list`, `issue_list`, `progress_row` already exist. Import and use.
- **`Projects.Dashboard` issue detectors** — Plan 1 may already have `detect_unused_variables/1` and `detect_empty_sheets/1`. Extend or reuse, do NOT recreate.
- **Variable queries** — `Sheets.list_project_variables/1` already returns all variables with metadata. Do NOT write a second "list all variables" query.
- **Variable usage** — `Flows.count_variable_usage/1` exists (per-block). For a ranking, you may need a project-level aggregation — add it to Dashboard or a new Sheets query, NOT by calling the per-block function in a loop.

### Existing queries — DO NOT duplicate
- `Sheets.count_sheets/1` — EXISTS in `sheet_queries.ex`
- `Sheets.list_project_variables/1` — EXISTS in `sheet_queries.ex` (returns full variable metadata)
- `Sheets.list_all_sheets/1` — EXISTS in `sheet_queries.ex`
- `Sheets.list_leaf_sheets/1` — EXISTS in `sheet_queries.ex`
- `Sheets.list_sheets_tree/1` — EXISTS in `sheet_queries.ex`
- `Flows.count_variable_usage/1` — EXISTS in `variable_reference_tracker.ex` (per-block)

### What to remove from SheetLive.Index
| Current Code | Action |
|-------------|--------|
| `sheet_card/1` helper component | **DELETE** — replaced by dashboard content |
| Card grid (`<div class="grid ...">`) | **DELETE** — replaced by dashboard sections |
| Header "Sheets" + subtitle | **KEEP or adapt** |
| `<.empty_state>` for zero sheets | **KEEP** |
| Create/delete/move event handlers | **KEEP** — user can still manage sheets from dashboard |
| Sidebar tree | **KEEP** — sheets dashboard keeps the tree sidebar |
| `show_pin={false}` + `tree_panel_open: true` | **KEEP** |

### New queries go in the RIGHT place
- Sheet-level stats (block count, completeness per sheet) → add to `Sheets` context, delegate through facade
- Variable usage aggregation across flows → could go in `Projects.Dashboard` (cross-context) or new query in `Sheets`
- Do NOT import Flow schemas directly in Sheet queries — go through facades

### Gettext domain
All user-facing text: `dgettext("sheets", "...")`.

---

## Research Phase (before implementation)

1. **What does a designer need to know about their sheets?**
   - Are all character/location sheets filled in? (completeness)
   - Which variables actually matter? (used in flows vs unused)
   - Which sheets are referenced most? (importance)
   - Are there data consistency issues? (empty required fields, orphan references)

2. **Existing queries to audit:**
   - `list_project_variables/1` — read actual return type and fields
   - `count_variable_usage/1` — understand the per-block approach
   - `list_leaf_sheets/1` — what exactly does "leaf" mean here
   - Block schema — what fields indicate "empty" vs "filled"

3. **What's missing?**
   - Per-sheet completeness score (filled blocks / total blocks) — needs definition of "filled"
   - Variable usage ranking (most referenced across all flows) — project-level aggregation
   - Sheet-to-flow dependency map — which flows reference which sheets
   - Empty/incomplete block detection

---

## Proposed Sections

### Section 1: Sheet Stats

Uses `stat_card` from `DashboardComponents`.

| Card | Metric | Query |
|------|--------|-------|
| Total Sheets | Count (leaf vs group) | `Sheets.count_sheets/1` (**exists**) |
| Total Variables | Variables defined | `length(Sheets.list_project_variables/1)` or NEW count query |
| Used Variables | Referenced in at least one flow | NEW query needed |
| Unused Variables | Defined but never referenced | NEW query (inverse of used) |

### Section 2: Variable Usage Ranking

Top variables by flow reference count. Shows which variables drive the narrative.

Uses `ranked_list` from `DashboardComponents`. Each row: variable name + sheet name + usage count + bar.

### Section 3: Sheet Completeness

Per-sheet fill rate — how many blocks have non-empty values vs total blocks. Helps find incomplete character sheets.

Table or progress bars per sheet.

### Section 4: Issues

Uses `issue_list` from `DashboardComponents`.

- Unused variables (defined, never referenced)
- Empty required blocks (blocks marked required but no value)
- Orphan references (reference blocks pointing to deleted sheets)
- Sheets with no variables (all blocks are constants — may be intentional, low severity)

---

## Task Checklist (to be detailed during implementation)

- [ ] Research: audit sheet queries, block schema, variable tracking — read actual code
- [ ] Design: finalize "empty" vs "filled" definition for blocks
- [ ] Implement: variable usage ranking query (project-level, efficient)
- [ ] Implement: sheet completeness query
- [ ] Implement: sheet-specific issue detectors
- [ ] Rewrite: `SheetLive.Index` render — delete card grid, add dashboard sections
- [ ] Cleanup: remove dead `sheet_card/1` helper, unused assigns
- [ ] Tests + verify: `mix precommit`
