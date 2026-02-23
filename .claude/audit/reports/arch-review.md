# Architecture Review

## Score: 78/100

| Dimension               | Score   | Weight  | Notes                                          |
|-------------------------|---------|---------|------------------------------------------------|
| Context Boundaries      | 72/100  | 25%     | Good facades, some cross-context leaks         |
| Module Organization     | 85/100  | 20%     | Consistent naming, well-structured directories |
| LiveView Structure      | 75/100  | 20%     | Thin dispatchers, but Repo leaks everywhere    |
| Schema Design           | 82/100  | 15%     | Good indexing, clean schemas                   |
| JavaScript Architecture | 80/100  | 10%     | Well-organized, mirrors server patterns        |
| Code Duplication        | 74/100  | 10%     | Shared abstractions exist, but gaps remain     |

## Findings

### Critical

**1. Repo leaks into LiveView layer (50+ occurrences)**

`Storyarn.Repo` is aliased and called directly in **28 LiveView files** with **50+ direct Repo calls** (preload, get_by, insert, update, all). This breaks the context boundary contract.

Worst offenders:
- `lib/storyarn_web/live/sheet_live/components/propagation_modal.ex` — raw `Repo.all()` with `Ecto.Query`
- `lib/storyarn_web/live/sheet_live/components/versions_section.ex` — 4 direct `Repo.preload` calls
- `lib/storyarn_web/live/sheet_live/helpers/asset_helpers.ex` — 5 direct `Repo.preload` calls
- `lib/storyarn_web/live/project_live/components/settings_components.ex` — `Repo.get_by`, `Repo.insert`, `Repo.update`
- `lib/storyarn_web/live/flow_live/nodes/dialogue/node.ex`, `exit/node.ex`, `scene/node.ex` — `Repo.preload`

**2. Eleven dependency cycles detected (xref)**

Most concerning:
- **Flows internal cycle (length 7):** `flows.ex` → `flow_crud.ex` → `node_create.ex` → `node_crud.ex` → `node_delete.ex` → `node_update.ex` → `variable_reference_tracker.ex`
- **Node type registry compile-time cycle (length 11):** Changing any node type module triggers recompilation of all node types
- **block_crud ↔ property_inheritance (length 2)**

**3. Cross-context data access in Sheets ↔ Flows**

Bidirectional coupling: Sheets aliases `Flows.VariableReferenceTracker`, `Flows.Flow`, `Flows.FlowNode`. Flows aliases `Sheets.Block`, `Sheets.Sheet`, `Sheets.TableColumn`, `Sheets.TableRow` and 5 constraint modules.

### Warnings

- `Shortcuts` module queries schemas from 4 different contexts directly
- `Maps` facade imports `Ecto.Query` and aliases `Repo` for a raw query
- `FlowLive.Show` has 1005 lines and 84+ handle_event clauses
- Large files: `table_blocks.ex` (1131), `element_handlers.ex` (1045), `undo_redo_handlers.ex` (1035)
- No anti-corruption layer for cross-context data
- Repeated `Repo.preload(project, :workspace)` in 12+ mount functions

### Good Patterns

- Consistent facade + defdelegate pattern across all 8 contexts
- Per-node-type architecture (2 files per node type, mirrored in JS)
- Shared abstractions: `SoftDelete`, `TreeOperations`, `NameNormalizer`
- Strong type specifications on all public facade functions
- Handler decomposition with focused handler modules
- Consistent `with_auth/3` authorization wrapper
- Good database indexing (composite, partial unique, FK indexes)
- JavaScript mirrors server architecture (38 hooks flat, per-type nodes)
- Clean Collaboration context — fully self-contained via PubSub

## Statistics

| Metric                            | Value              |
|-----------------------------------|--------------------|
| Elixir source files               | 339                |
| Total Elixir LOC                  | 67,188             |
| JavaScript LOC                    | 23,439             |
| Test files / LOC                  | 91 / 37,726        |
| Contexts                          | 8                  |
| Dependency cycles                 | 11 (3 non-trivial) |
| LiveViews with direct Repo access | 28                 |
| Files > 1000 LOC                  | 4                  |
