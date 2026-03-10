# Plan 2: Flows Dashboard

**Page:** `/workspaces/:ws/projects/:proj/flows` (`FlowLive.Index`)
**Current state:** Grid of flow cards showing name + description + "Main" badge
**Goal:** Replace card grid with a dashboard that helps the designer understand their narrative structure and find flow-level problems.
**Depends on:** Plan 1 (shared `DashboardComponents`, query patterns in `Dashboard` module)

---

## CRITICAL: Code Hygiene Rules

### Reuse from Plan 1
- **`DashboardComponents`** — `stat_card`, `ranked_list`, `issue_list` already exist from Plan 1. Do NOT recreate them. Import and use.
- **`Projects.Dashboard`** — If Plan 1 already implemented project-level `count_all_nodes_by_type/1`, reuse it. Do NOT write a second version.
- **Issue detection** — Plan 1 may already detect disconnected nodes and flows without entry at project level. For per-flow breakdown, extend existing functions (add optional `flow_id` parameter) rather than writing new ones.

### Existing queries — DO NOT duplicate
- `Flows.count_flows/1` — EXISTS in `flow_crud.ex`
- `Flows.count_nodes_for_project/1` — EXISTS in `flow_crud.ex`
- `Flows.count_nodes_by_type/1` — EXISTS in `node_crud.ex` (per-flow)
- `Flows.list_flows/1` — EXISTS in `flow_crud.ex`
- `Flows.list_flows_tree/1` — EXISTS in `flow_crud.ex`
- `Flows.list_speaker_sheet_ids/1` — EXISTS in `flow_crud.ex`

### What to remove from FlowLive.Index
The current file has flow card rendering logic (lines ~40-130 approx). This gets **replaced**, not commented out:

| Current Code | Action |
|-------------|--------|
| `flow_card/1` helper component | **DELETE** — replaced by table rows |
| Card grid rendering (`<div class="grid ...">`) | **DELETE** — replaced by dashboard sections |
| Header "Flows" + subtitle "Create visual narrative flows" | **KEEP or adapt** — dashboard still needs a title |
| `<.empty_state>` for zero flows | **KEEP** — still needed when project has no flows |
| Create/delete/move event handlers | **KEEP** — user can still create flows from dashboard |
| Sidebar tree (`:tree_content` slot) | **KEEP** — flows dashboard keeps the tree sidebar |
| `show_pin={false}` + `tree_panel_open: true` | **KEEP** — index always shows sidebar |

### New queries go in the RIGHT place
- Per-flow stats (node count, word count per flow) → add to `Flows` context (e.g., `FlowCrud` or new `FlowQueries` if needed), delegate through `Flows` facade
- Project-level flow aggregates → extend `Projects.Dashboard` if appropriate
- Do NOT put flow-specific queries in `Projects.Dashboard` — that module is for cross-context aggregation

### Gettext domain
All user-facing text: `dgettext("flows", "...")`. Not "projects", not hardcoded.

---

## Research Phase (before implementation)

Before implementing, investigate and answer:

1. **What does a narrative designer need to know about their flows?**
   - Which flows are the longest / most complex?
   - Which flows have the most branching (conditions)?
   - Which flows reference each other (subflow/jump graph)?
   - Where are the quality problems?

2. **What queries already exist?** (see list above — audit actual signatures and return types)

3. **What's missing?**
   - Per-flow word count (dialogue text) — NEW query in Flows context
   - Per-flow branching factor (avg outputs per condition node) — NEW
   - Cross-flow reference map (subflow/jump targets) — NEW
   - Per-flow issue detection (disconnected nodes, missing speakers) — extend Plan 1 detectors

---

## Proposed Sections

### Section 1: Flow Overview Stats (top row)

Uses `stat_card` from `DashboardComponents` (created in Plan 1).

| Card | Metric | Query |
|------|--------|-------|
| Total Flows | Count | `Flows.count_flows/1` (**exists**) |
| Total Nodes | Sum across all flows | `Flows.count_nodes_for_project/1` (**exists**) |
| Total Words | Sum of dialogue text | Reuse `Dashboard.count_total_words/1` from Plan 1, or per-flow if needed |
| Avg Branching | Avg condition outputs per flow | NEW query |

### Section 2: Flow Table (main content — replaces card grid)

Sortable table showing per-flow metrics. Uses `<.table>` from CoreComponents or a custom sortable table.

| Column | Data | Sortable |
|--------|------|----------|
| Name | Flow name (link to flow) | Yes |
| Nodes | Total node count | Yes |
| Dialogue | Dialogue node count | Yes |
| Conditions | Condition node count | Yes |
| Words | Word count from dialogue | Yes |
| Issues | Issue count (badge) | Yes |
| Last Modified | `updated_at` | Yes |

**Query approach:** Single query that returns per-flow stats. Do NOT make N+1 queries (one per flow). Use a subquery or JOIN approach:
```sql
SELECT f.id, f.name, f.updated_at,
       COUNT(n.id) as node_count,
       COUNT(n.id) FILTER (WHERE n.type = 'dialogue') as dialogue_count,
       COUNT(n.id) FILTER (WHERE n.type = 'condition') as condition_count
FROM flows f
LEFT JOIN flow_nodes n ON n.flow_id = f.id
WHERE f.project_id = ? AND f.deleted_at IS NULL AND n.deleted_at IS NULL
GROUP BY f.id
```

### Section 3: Flow Issues (expandable)

Uses `issue_list` from `DashboardComponents`. Per-flow issues:

| Issue | Detection |
|-------|-----------|
| Disconnected nodes | Nodes with no connections |
| Missing entry | Flow without entry node |
| Empty flow | Flow with 0 nodes |
| Missing speakers | Dialogue nodes with deleted/nil speaker_sheet_id |

**Note:** "Unreachable nodes" (graph traversal from entry) is complex. Defer to v2.

### Section 4: Flow Relationship Graph (stretch goal — v2)

Visual mini-map showing how flows connect via subflow/jump nodes. Start as a simple list view, graph visualization later. **Do NOT implement in first pass.**

---

## Task Checklist (to be detailed during implementation)

- [ ] Research: audit all existing flow queries — read actual function signatures and return types
- [ ] Design: finalize sections and components needed
- [ ] Implement: per-flow stats query in Flows context (single efficient query, NOT N+1)
- [ ] Implement: flow table with client-side sorting (or LiveView sorting via `handle_event`)
- [ ] Implement: flow issue detection (per-flow) — extend Plan 1 detectors
- [ ] Rewrite: `FlowLive.Index` render — delete card grid, add dashboard sections
- [ ] Cleanup: remove dead `flow_card/1` helper, unused assigns
- [ ] Tests: query tests + LiveView tests
- [ ] Verify: `mix precommit` — zero warnings, zero dead code
