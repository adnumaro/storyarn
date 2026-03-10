# Plan 1: Project Dashboard

**Page:** `/workspaces/:ws/projects/:proj` (`ProjectLive.Show`)
**Current state:** Placeholder — "Project workspace coming soon!"
**Goal:** Actionable project overview that answers "how is my project doing?"

---

## CRITICAL: Code Hygiene Rules

**These rules are non-negotiable. Violating them is a bug.**

### DO NOT duplicate existing queries
Before writing ANY query, check if it already exists:
- `Sheets.count_sheets/1` — EXISTS in `lib/storyarn/sheets/sheet_queries.ex`
- `Sheets.list_project_variables/1` — EXISTS in `lib/storyarn/sheets/sheet_queries.ex`
- `Flows.count_flows/1` — EXISTS in `lib/storyarn/flows/flow_crud.ex`
- `Flows.count_nodes_for_project/1` — EXISTS in `lib/storyarn/flows/flow_crud.ex`
- `Flows.count_nodes_by_type/1` — EXISTS in `lib/storyarn/flows/node_crud.ex`
- `Flows.list_speaker_sheet_ids/1` — EXISTS in `lib/storyarn/flows/flow_crud.ex`
- `Flows.count_variable_usage/1` — EXISTS in `lib/storyarn/flows/variable_reference_tracker.ex`
- `Scenes.count_scenes/1` — EXISTS in `lib/storyarn/scenes/scene_crud.ex`
- `Localization.Reports.progress_by_language/1` — EXISTS in `lib/storyarn/localization/reports.ex`
- `Localization.Reports.word_counts_by_speaker/2` — EXISTS in `lib/storyarn/localization/reports.ex`

**Call these through their facades** (`Sheets.count_sheets/1`, NOT `Sheets.SheetQueries.count_sheets/1`).

### DO NOT leave dead code
- The current `ProjectLive.Show` is a placeholder. **Delete the entire render function body and replace it** — do not comment out old code.
- The current mount loads `sheets_tree` for a sidebar that will no longer exist on this page. **Remove `sheets_tree` loading** and the `SheetTree` alias if the dashboard uses `Layouts.app` instead of `Layouts.focus`.
- Remove the `Storyarn.Sheets` alias and `SheetTree` import if no longer used.
- Remove the `handle_event("tree_panel_" <> ...)` handler and `TreePanelHandlers` import if no tree panel on this page.

### DO NOT write utilities that belong in shared modules
- Word count HTML stripping → If creating a reusable `strip_html_tags/1`, put it in `Storyarn.Shared` (or reuse `HtmlSanitizer` from `lib/storyarn_web/live/flow_live/helpers/html_sanitizer.ex`). Do NOT put it inline in the Dashboard module.
- Time formatting → Use `Storyarn.Shared.TimeHelpers` for `now/0`. Do NOT write `DateTime.utc_now() |> DateTime.truncate(:second)`.

### Facade pattern
All new public functions in `Dashboard` module MUST be delegated through `Storyarn.Projects` facade. LiveViews call `Projects.project_stats/1`, NEVER `Projects.Dashboard.project_stats/1`.

### Gettext
ALL user-facing text uses `dgettext("projects", "...")`. Zero hardcoded strings.

### Icons
Use Lucide icon names via `<.icon name="..." />`. Never Unicode emojis, never custom SVGs.

---

## Design Philosophy

The dashboard is NOT a vanity metrics page. Every section must either:
1. **Inform a decision** — "I should work on flows next, sheets are mostly done"
2. **Surface a problem** — "3 flows have disconnected nodes"
3. **Track progress** — "Localization is 60% complete for Spanish"

---

## What to Remove from `ProjectLive.Show`

The current file (`lib/storyarn_web/live/project_live/show.ex`) contains:

| Current Code | Action |
|-------------|--------|
| `import StoryarnWeb.Live.Shared.TreePanelHandlers` | **REMOVE** if using `Layouts.app` (no tree panel) |
| `alias Storyarn.Sheets` | **REMOVE** — dashboard doesn't load sheets tree |
| `alias StoryarnWeb.Components.Sidebar.SheetTree` | **REMOVE** — no sidebar tree |
| `Layouts.focus` wrapper with `:tree_content` slot | **REPLACE** with `Layouts.app` (or keep `Layouts.focus` if we want project sidebar — decide in Open Questions) |
| Placeholder div "Project workspace coming soon!" | **DELETE entirely** |
| `assign(:sheets_tree, sheets_tree)` in mount | **REMOVE** |
| `handle_event("tree_panel_" <> ...)` | **REMOVE** if no tree panel |

**After rewrite, the file should have zero references to sheets_tree, SheetTree, TreePanelHandlers, or "coming soon".**

---

## Sections

### Section 1: Project Health Summary (top row of stat cards)

Quick-glance numbers. Each card is clickable → navigates to the relevant tool.

| Card | Metric | Query | Icon |
|------|--------|-------|------|
| Sheets | Total sheets (non-deleted) | `Sheets.count_sheets/1` (**exists**) | `file-text` |
| Variables | Total variables defined | NEW `count_variables/1` (or `length(Sheets.list_project_variables/1)`) | `variable` |
| Flows | Total flows | `Flows.count_flows/1` (**exists**) | `git-branch` |
| Dialogue Lines | Total dialogue nodes | NEW `count_dialogue_nodes/1` (filter type=dialogue from nodes) | `message-square` |
| Scenes | Total scenes | `Scenes.count_scenes/1` (**exists**) | `map` |
| Words | Total word count across all dialogue | NEW `count_total_words/1` | `text` |

### Section 2: Content Breakdown (middle row)

Two side-by-side panels:

**Left: Node Distribution** (horizontal bar chart or stacked bar)
- Count of each node type across all flows (dialogue, condition, instruction, hub, etc.)
- Shows the "shape" of the narrative — heavy on dialogue? lots of branching?
- Query: NEW `count_all_nodes_by_type/1` — single query grouping by type across all project flows
- NOTE: `Flows.count_nodes_by_type/1` exists but is **per-flow**. The new query aggregates across the project. Do NOT call the per-flow version in a loop.

**Right: Top Speakers** (ranked list with avatars)
- Top 5-10 characters by dialogue line count
- Each row: avatar + name + line count + bar visualization
- Query: NEW `count_dialogue_lines_by_speaker/1` — group dialogue nodes by speaker_sheet_id, join sheet for name
- NOTE: `Flows.list_speaker_sheet_ids/1` exists but only returns IDs (no counts). The new query needs counts. Do NOT use list_speaker_sheet_ids and then count manually.
- Links to the character sheet on click

### Section 3: Issues & Warnings (actionable problems)

The differentiator. A list of detected issues, each clickable to navigate directly to the problem.

| Issue Type | Detection | Severity | Link Target |
|------------|-----------|----------|-------------|
| Disconnected flow nodes | Nodes with no input connections (except entry) and no output connections (except exit) | Warning | Flow show page |
| Empty sheets | Sheets with 0 blocks | Info | Sheet show page |
| Unused variables | Variables defined but never referenced in any flow condition/instruction | Info | Sheet block |
| Missing variable references | Flow conditions referencing variables that don't exist (stale references) | Error | Flow node |
| Flows without entry node | Flows missing an entry node | Error | Flow show page |
| Untranslated content | Localization texts pending translation (if languages configured) | Warning | Localization page |

**Implementation:** Each issue type is a separate lightweight query in `Dashboard`. Results collected into a unified list sorted by severity. Each issue struct: `%{severity: :error | :warning | :info, message: String.t(), href: String.t(), count: integer()}`.

### Section 4: Localization Progress (conditional — only if languages configured)

Only shown when the project has at least one target language configured.

- Progress bar per language (% translated)
- Total / translated / pending counts
- Query: `Localization.Reports.progress_by_language/1` (**exists, use as-is**)
- Link to localization page

### Section 5: Recent Activity (bottom)

Timeline of recent changes across all tools.

- "Sheet 'MC.Jaime' updated 2h ago"
- "Flow 'Chapter 1' — 3 nodes added today"
- "Scene 'Cryobay' created yesterday"

**Implementation:** Query `updated_at` across entity tables (sheets, flows, scenes, screenplays), union, sort by date, limit 10.

---

## Technical Implementation

### Task 1: Dashboard Query Module

**New file:** `lib/storyarn/projects/dashboard.ex`

This is the ONLY new module in the Projects context. All dashboard queries live here.

```elixir
defmodule Storyarn.Projects.Dashboard do
  @moduledoc "Aggregates dashboard data across all project contexts."

  import Ecto.Query
  alias Storyarn.Repo

  # Calls EXISTING facade functions — do NOT rewrite these queries
  alias Storyarn.Sheets
  alias Storyarn.Flows
  alias Storyarn.Scenes

  def project_stats(project_id) do
    %{
      sheet_count: Sheets.count_sheets(project_id),        # EXISTS
      variable_count: count_variables(project_id),          # NEW (below)
      flow_count: Flows.count_flows(project_id),            # EXISTS
      dialogue_count: count_dialogue_nodes(project_id),     # NEW (below)
      scene_count: Scenes.count_scenes(project_id),         # EXISTS
      total_word_count: count_total_words(project_id)       # NEW (below)
    }
  end

  # NEW queries — only what doesn't exist yet
  defp count_variables(project_id) do ... end
  def count_all_nodes_by_type(project_id) do ... end
  def count_dialogue_lines_by_speaker(project_id, limit \\ 10) do ... end
  def detect_issues(project_id) do ... end
  def recent_activity(project_id, limit \\ 10) do ... end
end
```

### Task 2: Delegates in Projects Facade

**Edit file:** `lib/storyarn/projects.ex`

Add delegates:
```elixir
# Dashboard
defdelegate project_stats(project_id), to: Storyarn.Projects.Dashboard
defdelegate count_all_nodes_by_type(project_id), to: Storyarn.Projects.Dashboard
defdelegate count_dialogue_lines_by_speaker(project_id), to: Storyarn.Projects.Dashboard
defdelegate detect_issues(project_id), to: Storyarn.Projects.Dashboard
defdelegate recent_activity(project_id, limit \\ 10), to: Storyarn.Projects.Dashboard
```

**Do NOT add delegates for private helpers** (count_variables, count_total_words, etc.).

### Task 3: New Queries Needed (all in Dashboard module)

| Query | Purpose | Notes |
|-------|---------|-------|
| `count_variables/1` | Count variables | Direct query on blocks table where `is_constant: false`, NOT `length(list_project_variables)` — avoid loading all rows just to count |
| `count_dialogue_nodes/1` | Count dialogue type nodes | Direct query on flow_nodes where type = "dialogue" and flow is in project |
| `count_total_words/1` | Sum word count from dialogue text | Strip HTML, count words. Consider doing in Elixir (load text fields, strip, count) or Postgres (regexp_replace + array_length). Start with Elixir approach — simpler. |
| `count_all_nodes_by_type/1` | Node type distribution | Single query: `group_by: :type, select: {type, count}` across all project flow nodes |
| `count_dialogue_lines_by_speaker/1` | Top speakers | Group dialogue nodes by speaker_sheet_id, count, LEFT JOIN sheet for name/avatar. Return `[%{sheet_id, sheet_name, avatar_url, line_count}]` |
| `detect_disconnected_nodes/1` | Issue: orphan nodes | Nodes not in any connection (neither source nor target), excluding entry/exit types |
| `detect_empty_sheets/1` | Issue: sheets with 0 blocks | Sheets with no blocks (LEFT JOIN blocks, HAVING count = 0) |
| `detect_unused_variables/1` | Issue: unused vars | Variables not referenced in flow_nodes data JSON. This is complex — consider skipping for v1 |
| `detect_flows_without_entry/1` | Issue: no entry node | Flows where no node has type = "entry" |
| `recent_activity/2` | Last N changes | Union of (sheets, flows, scenes) selecting `id, name, type, updated_at`, ordered desc, limited |

### Task 4: Dashboard Components

**New file:** `lib/storyarn_web/components/dashboard_components.ex`

Reusable across all 4 dashboard plans. Keep minimal — only what's needed now.

| Component | Purpose | Used by |
|-----------|---------|---------|
| `stat_card/1` | Clickable card with icon + label + value | Plan 1, 2, 3, 4 |
| `ranked_list/1` | Ordered list with bar visualization | Plan 1 (speakers), Plan 2 (flows), Plan 3 (variables) |
| `issue_list/1` | Issue rows with severity badge + link | Plan 1, 2, 3, 4 |
| `progress_row/1` | Progress bar with label + percentage | Plan 1 (localization) |

**Import in `storyarn_web.ex`?** No — only import in LiveViews that use it. Not every page needs dashboard components.

**Do NOT duplicate existing components:**
- `<.header>` already exists in CoreComponents — use it for section headers
- `<.empty_state>` already exists in UIComponents — use for empty dashboard state
- `<.icon>` already exists — use for all icons
- `<.link>` already exists — use for navigation

### Task 5: Rewrite ProjectLive.Show

**Edit file:** `lib/storyarn_web/live/project_live/show.ex`

**DELETE:**
- `import StoryarnWeb.Live.Shared.TreePanelHandlers`
- `alias Storyarn.Sheets`
- `alias StoryarnWeb.Components.Sidebar.SheetTree`
- Entire current `render/1` body
- `sheets_tree` loading in mount
- `handle_event("tree_panel_" <> ...)` clause

**ADD:**
- `import StoryarnWeb.Components.DashboardComponents`
- `alias Storyarn.Localization` (for progress, conditional)
- Async loading pattern with `send(self(), :load_dashboard_data)`
- New `render/1` with dashboard sections
- `handle_info(:load_dashboard_data, socket)` handler
- Loading skeleton states (show placeholder while data loads)

**Layout decision:** Use `Layouts.app` (main app shell with workspace sidebar), NOT `Layouts.focus` (no tree sidebar needed — this is an overview, not an editor). This means:
- Remove `focus_layout_defaults()` call
- Remove tree panel assigns
- Keep workspace/project assigns for the app layout header

### Task 6: Tests

**New file:** `test/storyarn/projects/dashboard_test.exs`

Test each query function with factory data:
- `project_stats/1` returns correct counts for project with sheets, flows, scenes
- `detect_issues/1` finds disconnected nodes, empty sheets, flows without entry
- `count_dialogue_lines_by_speaker/1` returns ranked list
- `recent_activity/1` returns sorted by date, respects limit

**Edit file:** `test/storyarn_web/live/project_live/show_test.exs`

Update existing tests (if any) or create:
- Dashboard renders stat cards with correct values
- Issue links navigate to correct pages
- Localization section hidden when no languages configured
- Empty project shows appropriate empty states (not broken)

---

## Task Checklist

- [ ] **T1:** Create `lib/storyarn/projects/dashboard.ex` with `project_stats/1` (calling existing facade functions)
- [ ] **T2:** Add new queries: `count_variables`, `count_dialogue_nodes`, `count_total_words`, `count_all_nodes_by_type`
- [ ] **T3:** Add `count_dialogue_lines_by_speaker/1` (with sheet join for name/avatar)
- [ ] **T4:** Add issue detectors: `detect_disconnected_nodes`, `detect_empty_sheets`, `detect_flows_without_entry`
- [ ] **T5:** Add `recent_activity/2` (union query across entity tables)
- [ ] **T6:** Add `defdelegate` entries in `lib/storyarn/projects.ex` facade
- [ ] **T7:** Create `lib/storyarn_web/components/dashboard_components.ex` (stat_card, ranked_list, issue_list, progress_row)
- [ ] **T8:** Rewrite `lib/storyarn_web/live/project_live/show.ex` — delete all placeholder code, replace with dashboard using `Layouts.app`
- [ ] **T9:** Add localization progress section (conditional on languages existing)
- [ ] **T10:** Write tests for Dashboard queries (`test/storyarn/projects/dashboard_test.exs`)
- [ ] **T11:** Update tests for ProjectLive.Show (`test/storyarn_web/live/project_live/show_test.exs`)
- [ ] **T12:** Run `mix precommit` — zero warnings, zero test failures
- [ ] **T13:** Verify no dead code: grep for "coming soon", `sheets_tree` in show.ex, unused aliases

---

## Open Questions

1. **Layout** — `Layouts.app` (recommendation) vs `Layouts.focus`. If `Layouts.app`, the project dashboard becomes a top-level page without the entity tree sidebar. The tool dropdown in the header still works for navigation. **Decision needed before T8.**

2. **Caching** — Start without caching. If queries are slow on large projects, add ETS/ConCache later. Do NOT premature-optimize.

3. **Word count precision** — Dialogue text is HTML. Use `String.replace(~r/<[^>]+>/, "")` to strip tags, then `String.split() |> length()` for word count. Do NOT use `HtmlSanitizer` (it sanitizes, doesn't strip). If this stripping logic is needed elsewhere later, extract to `Storyarn.Shared` — but for now keep it private in Dashboard.

4. **detect_unused_variables** — This requires parsing JSON `data` fields in flow_nodes to find variable references. Complex and potentially slow. **Defer to v2** — skip in initial implementation, mark as "coming soon" in the issues section if desired, or simply omit.
