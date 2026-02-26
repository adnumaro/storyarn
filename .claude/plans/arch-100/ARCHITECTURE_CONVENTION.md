# Architecture Convention — Boundary Rules

## The One Rule

**ALL external callers MUST go through the context facade.** No exceptions for function calls.

```
lib/storyarn/{context}.ex          ← ONLY entry point (facade)
lib/storyarn/{context}/            ← Internal submodules (NEVER called from outside)
lib/storyarn_web/                  ← Web layer (calls facades ONLY)
```

## What Goes Through the Facade

| Call Type | Must Use Facade? | Example |
|-----------|-----------------|---------|
| Function calls to submodules | **YES** | `Flows.condition_sanitize(c)` not `Condition.sanitize(c)` |
| Repo operations | **YES** | `Screenplays.import_fountain(...)` not `Repo.transaction(...)` |
| Storage/external service calls | **YES** | `Assets.upload(...)` not `Storage.upload(...)` |
| Struct pattern matching | **NO** (acceptable) | `alias Storyarn.Flows.FlowNode` for `%FlowNode{}` |
| Schema aliases for structs | **NO** (acceptable) | `alias Storyarn.Exports.ExportOptions` for `%ExportOptions{}` |
| `Storyarn.Shared.*` utilities | **NO** (shared layer) | `NameNormalizer.slugify(...)` is fine |
| `Storyarn.Accounts.Scope` | **NO** (ubiquitous) | Used everywhere for `current_scope` |

## Cross-Context Domain Calls

When context A needs context B's functionality, A calls B's **facade**, never B's submodules.

```elixir
# ✅ CORRECT — Flows calling Sheets facade
Sheets.update_block_references(block)
Sheets.count_backlinks("flow", flow_id)

# ❌ WRONG — Flows reaching into Sheets submodule
Storyarn.Sheets.ReferenceTracker.update_block_references(block)
```

**If the needed function doesn't exist on the facade, ADD IT as a `defdelegate`.**

## Naming Convention for Delegated Functions

When delegating submodule functions, use prefixed names to avoid collisions:

```elixir
# In Flows facade — Condition submodule
defdelegate condition_sanitize(condition), to: Condition, as: :sanitize
defdelegate condition_new(), to: Condition, as: :new
defdelegate condition_has_rules?(condition), to: Condition, as: :has_rules?

# In Flows facade — Instruction submodule
defdelegate instruction_sanitize(assignments), to: Instruction, as: :sanitize
defdelegate instruction_format_short(assignment), to: Instruction, as: :format_assignment_short

# In Flows facade — DebugSessionStore
defdelegate debug_session_store(key, data), to: DebugSessionStore, as: :store
defdelegate debug_session_take(key), to: DebugSessionStore, as: :take

# In Flows facade — NavigationHistoryStore
defdelegate nav_history_get(key), to: NavigationHistoryStore, as: :get
defdelegate nav_history_put(key, data), to: NavigationHistoryStore, as: :put
defdelegate nav_history_clear(key), to: NavigationHistoryStore, as: :clear
```

**Rationale:** Prefixing prevents name collisions (e.g., both Condition and Instruction have `sanitize/1`). The prefix uses the submodule concept in snake_case.

## Updating Call Sites

When updating web-layer callers:
1. **Remove** the alias to the submodule (`alias Storyarn.Flows.Condition`)
2. **Keep** the alias to the facade (`alias Storyarn.Flows`)
3. **Replace** all `Condition.function()` calls with `Flows.condition_function()`
4. **Verify** with `mix compile --warnings-as-errors`

## Verification Checklist

After changes:
```bash
mix compile --warnings-as-errors    # No warnings
mix format --check-formatted        # Formatted
mix test                            # Tests pass
```

Then grep to verify no remaining violations:
```bash
# Should return ZERO results (excluding struct aliases and Shared)
grep -rn "alias Storyarn\.\w\+\.\w\+\.\w\+" lib/storyarn_web/ --include="*.ex" | \
  grep -v "Evaluator.State\|FlowNode\|Flow\b\|Scope\|User\b\|Asset\b\|Scene\b\|Project\b\|Workspace\b\|Membership\|ExportOptions\|Screenplay\b" | \
  grep -v "Shared\.\|#"
```

---

## Known Cross-Context Repo JOIN Exceptions

The following modules contain **direct Ecto Repo JOINs across context boundaries**.
These are intentional trade-offs: refactoring them into facade calls would either
break single-query performance or require moving them to a shared module.

**Status:** Accepted technical debt. Revisit if these modules are refactored.

### 1. `Flows.VariableReferenceTracker` — JOINs on Sheets + Scenes schemas

**File:** `lib/storyarn/flows/variable_reference_tracker.ex`

Joins `Sheets.Block`, `Sheets.Sheet`, `Sheets.TableColumn`, `Sheets.TableRow`,
`Scenes.Scene`, `Scenes.ScenePin`, `Scenes.SceneZone` to resolve variable
references for flow nodes, scene zones, and scene pins.

**Why:** Variable reference tracking inherently bridges three contexts (Flows,
Sheets, Scenes). Each tracked entity needs to resolve sheet shortcuts and variable
names via JOINs. Breaking into facade calls would turn single queries into N+1
patterns or require duplicating schema knowledge across facades.

**Future fix options:**
- (A) Extract to `Storyarn.Shared.VariableReferenceTracker` (shared module)
- (B) Add batched facade queries to Sheets/Scenes and refactor to two-pass approach

### 2. `Sheets.ReferenceTracker` — JOINs on Flows + Screenplays schemas

**File:** `lib/storyarn/sheets/reference_tracker.ex` (lines ~215-261)

Joins `Flows.Flow`, `Flows.FlowNode`, `Screenplays.ScreenplayElement`,
`Screenplays.Screenplay` to resolve backlink sources (which flows/screenplays
reference a given sheet/block).

**Why:** Backlink resolution requires knowing the *source* entity's name and
parent for display. A single JOIN query is far more efficient than fetching
IDs first, then resolving names through facades.

**Future fix options:**
- (A) Add `Flows.resolve_node_backlinks/3` and `Screenplays.resolve_element_backlinks/3` facade functions
- (B) Move backlink resolution to a shared `ReferenceResolver` module

### 3. `Sheets.SheetQueries` — JOIN on Scenes schemas

**File:** `lib/storyarn/sheets/sheet_queries.ex` (function `list_pin_referenced_sheet_ids`)

Joins `Scenes.ScenePin`, `Scenes.Scene` to find which sheets are referenced
by scene pins in a project.

**Why:** Single query for export validation. Low impact.

**Future fix:** Move query to `Scenes.list_pin_referenced_sheet_ids/1` facade function.

### 4. `Assets` facade — JOINs on Flows + Sheets schemas

**File:** `lib/storyarn/assets.ex` (function `get_asset_usages/2`, lines ~262-295)

Joins `Flows.Flow`, `Flows.FlowNode`, `Sheets.Sheet` to find where an asset
is used across the project (for the asset detail/usage panel).

**Why:** Single query returning usage locations across all contexts.

**Future fix:** Add `Flows.list_nodes_using_asset/2` and `Sheets.list_sheets_using_asset/3` facade functions.

### 5. `Flows.FlowCrud` — JOINs on Sheets + Scenes schemas

**File:** `lib/storyarn/flows/flow_crud.ex` (lines ~516, 548-550)

Joins `Sheets.Block`, `Sheets.Sheet`, `Scenes.Scene` for variable-related
queries within flow CRUD operations.

**Why:** Part of the variable reference resolution pipeline, same reason as #1.
