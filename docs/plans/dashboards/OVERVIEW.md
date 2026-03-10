# Dashboards — Execution Overview

## Vision

Replace empty/redundant index pages with **actionable dashboards** that help narrative designers understand their project's state, find problems, and make decisions. No competitor (articy, Twine, Ink, Yarn Spinner) offers analytics dashboards — this is a differentiator.

## Execution Order

| #  | Plan                        | Page                                  | Priority | Depends On |
|----|-----------------------------|---------------------------------------|----------|------------|
| 1  | **Project Dashboard**       | `/workspaces/:ws/projects/:proj`      | High     | —          |
| 2  | **Flows Dashboard**         | `/workspaces/:ws/projects/:proj/flows`| Medium   | Plan 1     |
| 3  | **Sheets Dashboard**        | `/workspaces/:ws/projects/:proj/sheets`| Medium  | Plan 1     |
| 4  | **Scenes Dashboard**        | `/workspaces/:ws/projects/:proj/scenes`| Low     | Plan 1     |

**Screenplays excluded** — behind super_admin gate, not ready for dashboards yet.

## Why This Order

1. **Project Dashboard first** — Currently a placeholder ("coming soon"). Highest impact. Establishes shared query infrastructure (`Projects.Dashboard` module) and component library (`DashboardComponents`) that all subsequent plans reuse.

2. **Flows second** — Core editing tool. Most data already queryable. Highest value for the designer after the project overview.

3. **Sheets third** — Variable completeness and usage tracking. Valuable but secondary.

4. **Scenes last** — Least data to surface currently. Visual tool — analytics less critical.

## Global Code Hygiene Rules

**Every plan contains its own "CRITICAL: Code Hygiene Rules" section. These are mandatory.**

Key principles enforced across ALL plans:

1. **No duplicate queries** — Each plan lists existing queries that MUST be reused, not rewritten. Call through facades.
2. **No dead code** — Each plan lists exactly what to DELETE from the current index page. No commenting out, no `_unused` prefixes on code that should be removed.
3. **No duplicate components** — `DashboardComponents` is created ONCE in Plan 1. Plans 2-4 import and use it. Never recreate `stat_card` etc.
4. **Right module, right place** — Per-context queries go in that context's modules. Cross-context aggregation goes in `Projects.Dashboard`. Never import schemas cross-context.
5. **Facade pattern** — All public functions delegated through context facades. LiveViews never call submodules directly.
6. **Gettext always** — Zero hardcoded user-facing strings. Each plan specifies its Gettext domain.

## Shared Infrastructure (Built in Plan 1, Reused by Plans 2-4)

| Artifact | File | Purpose |
|----------|------|---------|
| `Projects.Dashboard` | `lib/storyarn/projects/dashboard.ex` | Cross-context aggregation queries |
| `DashboardComponents` | `lib/storyarn_web/components/dashboard_components.ex` | `stat_card`, `ranked_list`, `issue_list`, `progress_row` |
| Async loading pattern | In `ProjectLive.Show` | `send(self(), :load_dashboard_data)` pattern — copy for Plans 2-4 |

## Plan Files

| Plan | File |
|------|------|
| Project Dashboard | `docs/plans/dashboards/01-project-dashboard.md` |
| Flows Dashboard   | `docs/plans/dashboards/02-flows-dashboard.md` |
| Sheets Dashboard  | `docs/plans/dashboards/03-sheets-dashboard.md` |
| Scenes Dashboard  | `docs/plans/dashboards/04-scenes-dashboard.md` |
