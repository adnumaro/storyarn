# Plan 4: Scenes Dashboard

**Page:** `/workspaces/:ws/projects/:proj/scenes` (`SceneLive.Index`)
**Current state:** Grid of scene cards showing name + description + shortcut
**Goal:** Dashboard showing world-building coverage, scene connectivity, and asset usage.
**Depends on:** Plan 1 (shared `DashboardComponents`)

---

## CRITICAL: Code Hygiene Rules

### Reuse from Plans 1, 2, 3
- **`DashboardComponents`** — all components already exist. Import and use, do NOT recreate.
- **`Projects.Dashboard` issue detectors** — Check if any scene-related detectors were added in Plan 1. Extend, don't duplicate.

### Existing queries — DO NOT duplicate
- `Scenes.count_scenes/1` — EXISTS in `scene_crud.ex`
- `Scenes.list_scenes/1` — EXISTS
- `Scenes.list_scenes_tree/1` — EXISTS

### What to remove from SceneLive.Index
| Current Code | Action |
|-------------|--------|
| Scene card rendering (card grid) | **DELETE** — replaced by dashboard content |
| Header "Scenes" + subtitle | **KEEP or adapt** |
| `<.empty_state>` | **KEEP** |
| Create/delete/move event handlers | **KEEP** |
| Sidebar tree + tab toggle (Scenes/Layers) | **KEEP** |
| `show_pin={false}` + `tree_panel_open: true` | **KEEP** |

### New queries go in the RIGHT place
- Scene-level stats (zone/pin count per scene) → add to `Scenes` context, delegate through facade
- Scene-to-flow linkage → cross-context query, goes in `Projects.Dashboard`
- Do NOT import Flow schemas in Scene queries

### Gettext domain
All user-facing text: `dgettext("scenes", "...")`.

---

## Research Phase (before implementation)

1. **What does a designer need to know about their scenes?**
   - Which scenes are connected to flows? (narrative coverage)
   - Which scenes have zones/pins configured? (interactivity)
   - Which scenes are missing background images? (asset coverage)
   - How do scenes connect to each other? (world graph)

2. **Existing queries to audit:**
   - `count_scenes/1` — read actual implementation
   - Zone/pin/connection CRUD — what list queries exist
   - Layer schema — what indicates "has background image"
   - Scene connection schema — how scenes link to each other
   - Flow slug_line node data — how flows reference scenes (if at all)

3. **What's missing?**
   - Per-scene complexity score (zones + pins + connections)
   - Scene-to-flow linkage (which flows reference which scenes via slug_line nodes)
   - Asset coverage (scenes/layers with vs without background images)
   - Scene connectivity summary

---

## Proposed Sections

### Section 1: Scene Stats

Uses `stat_card` from `DashboardComponents`.

| Card | Metric | Query |
|------|--------|-------|
| Total Scenes | Count | `Scenes.count_scenes/1` (**exists**) |
| Total Zones | Interactive zones across all scenes | NEW aggregate query |
| Total Pins | Pins across all scenes | NEW aggregate query |
| Connected to Flows | Scenes referenced by flow slug_line nodes | NEW cross-context query |

### Section 2: Scene Table

Per-scene metrics: layers, zones, pins, connections, has background, linked flows.

Uses sortable table (same pattern as Plan 2's flow table).

### Section 3: Issues

Uses `issue_list` from `DashboardComponents`.

- Scenes with no layers
- Scenes/layers with no background image
- Scenes not referenced by any flow
- Zones without connections (dead-end interactions)

---

## Task Checklist (to be detailed during implementation)

- [ ] Research: audit scene queries, zone/pin/connection schemas, layer background field
- [ ] Design: finalize sections and what "connected to flow" means technically
- [ ] Implement: scene stats aggregate queries in Scenes context
- [ ] Implement: scene-to-flow linkage query (cross-context, in Dashboard or Scenes)
- [ ] Implement: scene issue detectors
- [ ] Rewrite: `SceneLive.Index` render — delete card grid, add dashboard sections
- [ ] Cleanup: remove dead card rendering code, unused assigns
- [ ] Tests + verify: `mix precommit`
