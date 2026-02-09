# Screenplay Tool Implementation Plan

> **Goal:** Add a new top-level tool "Screenplays" alongside Flows and Sheets that provides a professional screenplay editor with bidirectional sync to Flows.
>
> **Priority:** Major feature
>
> **Last Updated:** February 9, 2026

## Overview

Screenplay is a **block-based screenplay editor** where each block maps to a flow node (and vice versa). It's a new top-level entity in the project sidebar, alongside Sheets and Flows.

**Key Principles:**
- Screenplay is an **independent entity** — can exist without a linked flow
- When linked to a flow, edits in either sync bidirectionally
- Uses industry-standard screenplay formatting (Fountain-compatible)
- Slash commands (`/conditional`, `/instruction`, etc.) create special blocks
- Each block maps to a flow node; consecutive character+dialogue blocks group into one node

**Industry Format Reference:** Courier 12pt monospaced, specific margins per element type. See [Fountain syntax spec](https://fountain.io/syntax/) for the text-based screenplay format standard.

---

## Implementation Status

| Phase   | Name                                                | Priority     | Status   |
|---------|-----------------------------------------------------|--------------|----------|
| 1       | Database & Context                                  | Essential    | Done     |
| 2       | Sidebar & Navigation                                | Essential    | Pending  |
| 3       | Screenplay Editor (Core Blocks)                     | Essential    | Pending  |
| 4       | Slash Command System                                | Essential    | Pending  |
| 5       | Interactive Blocks (Condition/Instruction/Response) | Essential    | Pending  |
| 6       | Flow Sync — Screenplay → Flow                       | Essential    | Pending  |
| 7       | Flow Sync — Flow → Screenplay                       | Essential    | Pending  |
| 8       | Dual Dialogue & Advanced Formatting                 | Important    | Pending  |
| 9       | Title Page & Export                                 | Nice to Have | Pending  |

### Phase 1 — Detailed Task Breakdown

| Task | Name                                  | Status  | Tests |
|------|---------------------------------------|---------|-------|
| 1.1  | Migration: create_screenplays         | Done    | N/A   |
| 1.2  | Screenplay schema + changesets        | Done    | 25 pass |
| 1.3  | ScreenplayElement schema + changesets | Done    | 29 pass |
| 1.4  | ScreenplayCrud + test fixtures        | Done    | 18 pass |
| 1.5  | ElementCrud                           | Done    | 16 pass |
| 1.6  | ScreenplayQueries + TreeOperations    | Done    | 10 pass |
| 1.7  | ElementGrouping                       | Done    | 17 pass |
| 1.8  | Context facade (Screenplays.ex)       | Done    | 2 pass |

#### Task 1.1 — Migration: `create_screenplays`

**Goal:** Create the database tables for `screenplays` and `screenplay_elements`.

**File:** `priv/repo/migrations/TIMESTAMP_create_screenplays.exs`

**Details:**
- Follow the exact pattern from `20260201120005_create_flows.exs` migration
- Create `screenplays` table with fields: `name` (string, not null), `shortcut` (string), `description` (string), `position` (integer, default 0), `deleted_at` (utc_datetime), `project_id` (FK → projects, on_delete: delete_all), `parent_id` (FK → screenplays, on_delete: nilify_all), `linked_flow_id` (FK → flows, on_delete: nilify_all), `draft_of_id` (FK → screenplays, on_delete: delete_all), `draft_label` (string), `draft_status` (string, default "active"), timestamps
- Create indexes: `[:project_id]`, `[:parent_id]`, `[:project_id, :parent_id, :position]`, `[:deleted_at]`, `[:linked_flow_id]`, `[:draft_of_id]`
- Create unique partial index on `[:project_id, :shortcut]` WHERE `shortcut IS NOT NULL AND deleted_at IS NULL`
- Create unique partial index on `[:linked_flow_id]` WHERE `linked_flow_id IS NOT NULL AND deleted_at IS NULL` (Edge Case A)
- Create `screenplay_elements` table with fields: `type` (string, not null), `position` (integer, default 0, not null), `content` (text, default ""), `data` (map, default %{}), `depth` (integer, default 0), `branch` (string), `screenplay_id` (FK → screenplays, on_delete: delete_all, not null), `linked_node_id` (FK → flow_nodes, on_delete: nilify_all), timestamps
- Create indexes: `[:screenplay_id]`, `[:screenplay_id, :position]`, `[:linked_node_id]`
- **NO** `group_id` column (Edge Case F: dialogue groups computed from adjacency)

**Verification:** `mix ecto.migrate` runs without errors. `mix ecto.rollback` works cleanly.

**No tests needed** — migration correctness is verified by successful migrate/rollback.

---

#### Task 1.2 — Screenplay Schema + Changesets

**Goal:** Create the `Screenplay` Ecto schema with all changesets.

**Files:**
- `lib/storyarn/screenplays/screenplay.ex`
- `test/storyarn/screenplays/screenplay_test.exs`

**Details:**
- Follow the exact pattern from `lib/storyarn/flows/flow.ex`
- Schema fields match the migration: `name`, `shortcut`, `description`, `position`, `deleted_at`, `draft_label`, `draft_status`
- Relationships: `belongs_to :project` (Storyarn.Projects.Project), `belongs_to :parent` (__MODULE__), `belongs_to :linked_flow` (Storyarn.Flows.Flow), `belongs_to :draft_of` (__MODULE__), `has_many :children` (__MODULE__, foreign_key: :parent_id), `has_many :drafts` (__MODULE__, foreign_key: :draft_of_id), `has_many :elements` (Storyarn.Screenplays.ScreenplayElement)
- Helper: `draft?/1` — returns true if `draft_of_id` is not nil
- Changesets (follow Flow pattern):
  - `create_changeset/2` — validates name required, 1-200 chars; auto-generates shortcut if not provided (reuse `Storyarn.Shortcuts` module pattern from flows)
  - `update_changeset/2` — updates name, shortcut, description
  - `move_changeset/2` — updates parent_id, position
  - `delete_changeset/1` — sets deleted_at to now
  - `restore_changeset/1` — sets deleted_at to nil
  - `link_flow_changeset/2` — updates linked_flow_id

**Tests** (`test/storyarn/screenplays/screenplay_test.exs`):
- Valid create changeset with name
- Create changeset requires name
- Create changeset rejects name > 200 chars
- Update changeset works
- Delete changeset sets deleted_at
- Restore changeset clears deleted_at
- `draft?/1` returns true when draft_of_id is set
- `draft?/1` returns false when draft_of_id is nil

---

#### Task 1.3 — ScreenplayElement Schema + Changesets

**Goal:** Create the `ScreenplayElement` Ecto schema with changesets and type helpers.

**Files:**
- `lib/storyarn/screenplays/screenplay_element.ex`
- `test/storyarn/screenplays/screenplay_element_test.exs`

**Details:**
- Schema fields match migration: `type`, `position`, `content`, `data`, `depth`, `branch`
- Relationships: `belongs_to :screenplay`, `belongs_to :linked_node` (Storyarn.Flows.FlowNode)
- Module attribute `@element_types` with all 14 types: `scene_heading`, `action`, `character`, `dialogue`, `parenthetical`, `transition`, `dual_dialogue`, `conditional`, `instruction`, `response`, `hub_marker`, `jump_marker`, `note`, `section`, `page_break`, `title_page`
- Public functions: `types/0`, `standard_types/0`, `interactive_types/0`, `flow_marker_types/0`, `dialogue_group_types/0`, `non_mappeable_types/0`
- Changesets:
  - `create_changeset/2` — validates type in @element_types, position >= 0, content is string, depth >= 0, branch in [nil, "true", "false"]
  - `update_changeset/2` — updates content, data, type, depth, branch
  - `position_changeset/2` — updates position only
  - `link_node_changeset/2` — updates linked_node_id

**Tests** (`test/storyarn/screenplays/screenplay_element_test.exs`):
- Valid create changeset for each standard type
- Create changeset rejects invalid type
- Create changeset rejects negative position
- Branch validates only nil, "true", "false"
- `types/0` returns all 14 types
- `standard_types/0` returns correct subset
- `interactive_types/0` returns conditional, instruction, response
- `flow_marker_types/0` returns hub_marker, jump_marker
- `dialogue_group_types/0` returns character, dialogue, parenthetical
- `non_mappeable_types/0` returns note, section, page_break, title_page

---

#### Task 1.4 — ScreenplayCrud + Test Fixtures

**Goal:** Implement CRUD operations for screenplays and create test fixtures.

**Files:**
- `lib/storyarn/screenplays/screenplay_crud.ex`
- `test/support/fixtures/screenplays_fixtures.ex`
- `test/storyarn/screenplays/screenplay_crud_test.exs`

**Details — ScreenplayCrud** (follow `lib/storyarn/flows/flow_crud.ex` pattern):
- `create_screenplay/2` — receives project struct + attrs map. Auto-assigns position (max position + 1 among siblings). Inserts via Repo. Does NOT auto-create elements (unlike flows which auto-create entry/exit nodes).
- `get_screenplay!/2` — receives project_id + screenplay_id. Raises if not found. Filters `deleted_at IS NULL` and `draft_of_id IS NULL`. Preloads elements ordered by position.
- `get_screenplay/2` — same but returns nil instead of raising.
- `update_screenplay/2` — receives screenplay + attrs. Uses update_changeset.
- `delete_screenplay/1` — soft delete. Uses delete_changeset. Also recursively soft-deletes children (same pattern as FlowCrud).
- `restore_screenplay/1` — restore from soft delete. Uses restore_changeset.
- `list_deleted_screenplays/1` — lists soft-deleted screenplays for a project (for trash/restore UI).

**Details — Test Fixtures** (follow `test/support/fixtures/flows_fixtures.ex` pattern):
- `unique_screenplay_name/0` — returns "Screenplay #{System.unique_integer([:positive])}"
- `valid_screenplay_attributes/1` — merges defaults with provided attrs
- `screenplay_fixture/2` — creates a screenplay for a project (project defaults to project_fixture())
- `element_fixture/2` — creates a screenplay element (defaults: type "action", content "Test action")

**Tests** (`test/storyarn/screenplays/screenplay_crud_test.exs`):
- `create_screenplay/2` creates with valid attrs
- `create_screenplay/2` fails without name
- `create_screenplay/2` auto-assigns position
- `get_screenplay!/2` returns screenplay with elements preloaded
- `get_screenplay!/2` raises for deleted screenplay
- `get_screenplay!/2` raises for draft screenplay (draft_of_id not nil)
- `update_screenplay/2` updates name and description
- `delete_screenplay/1` soft-deletes (sets deleted_at)
- `delete_screenplay/1` recursively deletes children
- `restore_screenplay/1` clears deleted_at
- `list_deleted_screenplays/1` returns only deleted screenplays

---

#### Task 1.5 — ElementCrud

**Goal:** Implement CRUD operations for screenplay elements including insert-at-position and reorder.

**Files:**
- `lib/storyarn/screenplays/element_crud.ex`
- `test/storyarn/screenplays/element_crud_test.exs`

**Details** (no direct Flow equivalent — this is new logic):
- `list_elements/1` — all elements for a screenplay_id, ordered by position ASC
- `create_element/2` — receives screenplay struct + attrs. Appends at end (position = max + 1).
- `insert_element_at/3` — receives screenplay struct, position integer, attrs map. In a transaction: shift all elements with position >= target position by +1, then insert new element at target position. Returns `{:ok, element}`.
- `update_element/2` — receives element + attrs. Updates content, data, type, depth, branch.
- `delete_element/1` — receives element. In a transaction: delete element, then compact positions (shift down all elements after deleted one by -1). Returns `{:ok, element}`.
- `reorder_elements/2` — receives screenplay_id + ordered list of element IDs. In a transaction: update each element's position to its index in the list. Returns `{:ok, elements}`.
- `split_element/3` — receives element, cursor_position (integer), new_type (string). In a transaction:
  1. Split element.content at cursor_position into `before_text` and `after_text`
  2. Update current element content to `before_text`
  3. Insert new element of `new_type` at position + 1 with empty content
  4. Insert third element (same type as original) at position + 2 with `after_text`
  5. Shift all subsequent elements by +2
  Returns `{:ok, before_element, new_element, after_element}`.

**Tests** (`test/storyarn/screenplays/element_crud_test.exs`):
- `list_elements/1` returns elements ordered by position
- `create_element/2` appends at end with correct position
- `insert_element_at/3` inserts at position 0 (beginning)
- `insert_element_at/3` inserts in the middle, shifts subsequent
- `insert_element_at/3` inserts at end
- `update_element/2` updates content and data
- `update_element/2` can change element type
- `delete_element/1` removes element and compacts positions
- `delete_element/1` on last element works (no compaction needed)
- `reorder_elements/2` reorders elements by ID list
- `split_element/3` splits content correctly (middle of text)
- `split_element/3` splits at beginning (before = empty)
- `split_element/3` splits at end (after = empty)
- `split_element/3` shifts subsequent element positions by +2

---

#### Task 1.6 — ScreenplayQueries + TreeOperations

**Goal:** Implement read-only queries and tree reordering operations.

**Files:**
- `lib/storyarn/screenplays/screenplay_queries.ex`
- `lib/storyarn/screenplays/tree_operations.ex`
- `test/storyarn/screenplays/screenplay_queries_test.exs`
- `test/storyarn/screenplays/tree_operations_test.exs`

**Details — ScreenplayQueries:**
- `list_screenplays_tree/1` — receives project_id. Returns flat list of non-deleted, non-draft screenplays ordered by position. Build tree in memory (same pattern as `Flows.FlowCrud.build_tree/1`). Excludes drafts (`WHERE draft_of_id IS NULL AND deleted_at IS NULL`).
- `get_with_elements/1` — receives screenplay_id. Returns screenplay with elements preloaded (ordered by position).
- `count_elements/1` — receives screenplay_id. Returns integer count of elements.
- `list_drafts/1` — receives screenplay_id (the original). Returns all drafts where `draft_of_id = screenplay_id` and `deleted_at IS NULL`.

**Details — TreeOperations** (copy pattern from `lib/storyarn/flows/tree_operations.ex`):
- `reorder_screenplays/3` — receives project_id, parent_id, list of screenplay_ids. In a transaction: update position of each screenplay to its index. Returns `{:ok, screenplays}`.
- `move_screenplay_to_position/3` — receives screenplay, parent_id, position. Updates parent_id and position. Returns `{:ok, screenplay}`.

**Tests — ScreenplayQueries:**
- `list_screenplays_tree/1` returns tree structure
- `list_screenplays_tree/1` excludes deleted screenplays
- `list_screenplays_tree/1` excludes drafts
- `list_screenplays_tree/1` orders by position
- `get_with_elements/1` preloads elements in order
- `count_elements/1` returns correct count
- `count_elements/1` returns 0 for empty screenplay
- `list_drafts/1` returns drafts of a screenplay
- `list_drafts/1` excludes deleted drafts

**Tests — TreeOperations:**
- `reorder_screenplays/3` updates positions
- `move_screenplay_to_position/3` moves to new parent
- `move_screenplay_to_position/3` moves to root (parent_id = nil)

---

#### Task 1.7 — ElementGrouping

**Goal:** Implement dialogue group computation from element adjacency (Edge Case F).

**Files:**
- `lib/storyarn/screenplays/element_grouping.ex`
- `test/storyarn/screenplays/element_grouping_test.exs`

**Details:**
- `compute_dialogue_groups/1` — receives list of elements (ordered by position). Returns elements annotated with a computed `group_id` (virtual, not stored). Rules:
  - `character` starts a new group (generates UUID-based group_id)
  - `parenthetical` continues current group if preceded by `character` or `dialogue`
  - `dialogue` continues current group if preceded by `character` or `parenthetical`
  - Any other type breaks the current group (group_id = nil)
  - Single-pass O(n) algorithm
  - Returns list of `{element, group_id}` tuples

- `group_elements/1` — receives list of elements (ordered by position). Groups consecutive elements into logical units that map to flow nodes. Returns list of `%{type: atom, elements: [element], group_id: string | nil}` structs. Grouping rules:
  - Consecutive character + parenthetical? + dialogue → one `:dialogue_group`
  - `scene_heading` alone → `:scene_heading`
  - `action` alone → `:action`
  - `transition` alone → `:transition`
  - `conditional` alone → `:conditional`
  - `instruction` alone → `:instruction`
  - `response` alone → `:response`
  - `dual_dialogue` alone → `:dual_dialogue`
  - `hub_marker` alone → `:hub_marker`
  - `jump_marker` alone → `:jump_marker`
  - `note`, `section`, `page_break`, `title_page` → `:non_mappeable`

**Tests** (`test/storyarn/screenplays/element_grouping_test.exs`):
- `compute_dialogue_groups/1` groups character + dialogue
- `compute_dialogue_groups/1` groups character + parenthetical + dialogue
- `compute_dialogue_groups/1` breaks group on non-dialogue type
- `compute_dialogue_groups/1` handles multiple consecutive groups
- `compute_dialogue_groups/1` returns nil group_id for non-dialogue elements
- `compute_dialogue_groups/1` handles empty list
- `group_elements/1` returns dialogue_group for character+dialogue
- `group_elements/1` returns individual groups for scene_heading, action, etc.
- `group_elements/1` attaches response to preceding dialogue group (if exists)
- `group_elements/1` marks orphan response as standalone
- `group_elements/1` returns non_mappeable for note/section/page_break/title_page
- `group_elements/1` handles mixed element sequence (realistic screenplay)

---

#### Task 1.8 — Context Facade (Screenplays.ex)

**Goal:** Create the top-level Screenplays context module that delegates to submodules.

**Files:**
- `lib/storyarn/screenplays.ex`
- `test/storyarn/screenplays_test.exs` (integration smoke tests)

**Details:**
- Follow the exact `defdelegate` pattern from `lib/storyarn/flows.ex`
- Alias all submodules: `ScreenplayCrud`, `ElementCrud`, `ScreenplayQueries`, `TreeOperations`, `ElementGrouping`
- Delegate all public functions (list from plan section 1.4)
- Do NOT include `FlowSync` delegates yet (Phases 6-7)

**Tests** (`test/storyarn/screenplays_test.exs`) — integration smoke tests:
- Create screenplay → add elements → list elements → verify order
- Create screenplay → delete → verify soft-deleted → restore → verify active
- Create elements → reorder → verify new positions
- Create elements → group_elements → verify grouping
- Create screenplay with children → list tree → verify hierarchy

---

---

## Known Edge Cases & Solutions

> **Added:** February 9, 2026
> These solutions address architectural issues identified during plan review.

### A. Multiple screenplays linked to the same flow

**Problem:** The schema doesn't prevent two screenplays from linking to the same flow, causing sync conflicts.

**Solution:** Unique partial index on `linked_flow_id`:

```elixir
create unique_index(:screenplays, [:linked_flow_id],
  where: "linked_flow_id IS NOT NULL AND deleted_at IS NULL",
  name: :screenplays_linked_flow_unique
)
```

If a user tries to link a second screenplay to an already-linked flow, show a flash error identifying which screenplay already owns the link.

### B. Distinguishing auto-generated vs manual flow nodes

**Problem:** `sync_to_flow` needs to know which nodes it created (safe to update/delete) vs which the user added manually in the canvas (must preserve).

**Solution:** Add a `source` field to `flow_nodes`:

```elixir
# Migration: add_source_to_flow_nodes
add :source, :string, default: "manual"  # "manual" | "screenplay_sync"
```

- Nodes created by `sync_to_flow` are marked `"screenplay_sync"`
- Nodes created from the flow canvas remain `"manual"`
- Sync operations only touch nodes with `source = "screenplay_sync"`

### C. Destructive sync (clear + recreate)

**Problem:** Both sync directions do full clear + recreate, losing manual canvas positions (XY), writer notes, sections, and page breaks.

**Solution:** Diff-based sync instead of clear + recreate.

**sync_to_flow:**
1. Load existing nodes where `source = "screenplay_sync"`
2. Build map `{linked_node_id => existing node}`
3. For each element group:
   - If `linked_node_id` exists in map → **update** node data (preserve position_x/y)
   - If not → **create** new node, set `source = "screenplay_sync"`
4. Synced nodes no longer mapped to any element → **delete**
5. Nodes with `source = "manual"` → **never touch**

**sync_from_flow:**
1. Load existing elements with `linked_node_id`
2. Build map `{linked_node_id => element}`
3. For each flow node:
   - If element exists → **update** content/data
   - If not → **create** new element
4. Mappeable elements with no corresponding node → **delete**
5. Non-mappeable elements (note, section, page_break, title_page) → **always preserve**

### D. Hub/Jump nodes lose information when synced to screenplay

**Problem:** The plan maps hub → note and jump → note, losing navigation data. Round-trip sync destroys hubs/jumps.

**Solution:** Add `hub_marker` and `jump_marker` element types:

```elixir
# Add to @element_types
~w(... hub_marker jump_marker)

# hub_marker — preserves hub data for round-trip
%{type: "hub_marker", content: "Hub: Tavern Encounters", data: %{"hub_node_id" => 42, "color" => "blue"}}

# jump_marker — preserves jump target data for round-trip
%{type: "jump_marker", content: "-> Jump to: Tavern Encounters", data: %{"target_hub_id" => 42, "target_flow_id" => nil}}
```

These render as non-editable visual badges in the screenplay editor. On sync_to_flow they reconstruct as proper hub/jump nodes with all data intact.

### E. Response block without preceding dialogue

**Problem:** Response elements map to "add responses to PREVIOUS dialogue node" but the user may create a response with no dialogue before it.

**Solution:** Soft validation + fallback.

- **On creation:** When `/response` is selected, check if the preceding element is a dialogue group. If not, show a flash warning but allow creation anyway (writer may be working out of order).
- **Visual indicator:** Orphaned response blocks show a warning icon with tooltip "No preceding dialogue — responses won't sync to flow."
- **On sync_to_flow:** An orphaned response auto-generates a dialogue node wrapper with empty text + the responses attached. Not ideal but doesn't break the flow.

### F. Group ID management for dialogue groups

**Problem:** Stored `group_id` can become inconsistent when elements are reordered, inserted, or deleted.

**Solution:** Remove `group_id` from the schema entirely. Compute groups dynamically from adjacency in `ElementGrouping`:

```elixir
def compute_groups(elements) do
  # Consecutive character → parenthetical? → dialogue form a group
  # Rules:
  #   - character starts a new group
  #   - parenthetical continues if preceded by character or dialogue in same group
  #   - dialogue continues if preceded by character or parenthetical in same group
  #   - any other type breaks the group
end
```

Groups are derived from element order — impossible to become inconsistent. Cost is O(n) per computation on a list typically under 500 elements (trivial).

**Migration change:** Remove `group_id` column and its index from `screenplay_elements`.

### G. Nested conditionals (depth > 1)

**Problem:** The plan shows depth 0 and 1 but doesn't address conditionals inside conditionals.

**Solution:** The flat list model with `depth` + `branch` already supports arbitrary nesting. The rendering algorithm walks elements in order:

- `conditional` at depth N → start collecting branches at depth N+1
- Elements at depth N+1 with `branch = "true"` → render inside TRUE branch
- Elements at depth N+1 with `branch = "false"` → render inside FALSE branch
- When depth decreases back to N → branch collection ends

**UI limit:** The slash command menu does not offer `/conditional` when current depth >= 3 (practical limit). The data model and sync engine support unlimited depth.

### H. No collaboration for screenplay editor

**Problem:** Flows and Sheets have real-time collaboration (presence, locks, cursors). The screenplay plan doesn't mention it.

**Solution:** Reuse the existing `Collaboration` module with element-level locking.

- **Topic:** `screenplay:{id}` (same pattern as `flow:{id}`)
- **Presence:** Track online users via `Collaboration.track_presence/3`
- **Locks:** When a user focuses a `contenteditable` element, acquire lock on that element_id. Show colored border matching the collaborator's color on locked elements.
- **Changes:** Broadcast element updates so other LiveView sessions refresh.

No cursor tracking needed (no canvas). This is a subset of what flows already implement.

**When:** Implement in Phase 3 alongside the core editor, not as a later addition. Retrofitting locks onto an editor not designed for them is significantly harder.

### I. Soft-deleted linked flow/screenplay

**Problem:** If a flow is soft-deleted while a screenplay references it via `linked_flow_id`, the screenplay appears "linked" to a deleted entity.

**Solution:** Check link status on load, show warning UI.

```elixir
# In ScreenplayLive.Show mount:
link_status = cond do
  is_nil(screenplay.linked_flow_id) -> :unlinked
  flow = Flows.get_flow(screenplay.linked_flow_id) ->
    if flow.deleted_at, do: :flow_deleted, else: :linked
  true -> :flow_missing
end
```

- `:flow_deleted` → Banner: "The linked flow is in trash" + [Unlink] + [Restore flow] buttons
- `:flow_missing` → Banner: "The linked flow no longer exists" + [Unlink] button
- No blocking — the screenplay works independently regardless of link status.

### J. No undo/redo

**Problem:** A writing editor without undo is a significant UX risk.

**Solution:** Phased approach.

**Immediate (free):** Browser-native `contenteditable` undo (Cmd+Z) handles text editing within a single element. Works without any code.

**Later (Phase 3.5 or 4.5):** Session-level operation log for structural changes:

```elixir
# Stored in socket assigns (session-only, not persisted)
# Each structural operation (create, delete, reorder, change_type) pushes to undo_stack
assign(socket, :undo_stack, [])   # list of %{action, element_id, before, after}
assign(socket, :redo_stack, [])
```

- Ctrl+Z pops from undo_stack, applies `before` state, pushes to redo_stack
- Ctrl+Shift+Z does the inverse
- Stack limit: 50 operations
- Clears on page navigation (session-only)

This covers the 95% case. Full persistent undo history is deferred.

---

## Architecture

### Entity Relationship

```
Project
├── Sheets (data/variables)
├── Flows (visual graph)
└── Screenplays (formatted script) ← NEW
    ├── linked_flow_id (optional FK → flows)
    └── ScreenplayElement[] (ordered blocks)
```

### File Structure

```
lib/storyarn/
├── screenplays.ex                              # Context facade (defdelegate)
├── screenplays/
│   ├── screenplay.ex                           # Schema
│   ├── screenplay_element.ex                   # Schema (blocks)
│   ├── screenplay_crud.ex                      # CRUD operations
│   ├── element_crud.ex                         # Element CRUD + reordering
│   ├── screenplay_queries.ex                   # Read-only queries
│   ├── tree_operations.ex                      # Sidebar tree reordering
│   ├── flow_sync.ex                            # Bidirectional sync engine
│   └── element_grouping.ex                     # Group elements → flow nodes

lib/storyarn_web/
├── live/screenplay_live/
│   ├── index.ex                                # List/tree view
│   └── show.ex                                 # Screenplay editor
├── components/
│   ├── sidebar/screenplay_tree.ex              # Sidebar tree component
│   └── screenplay/
│       ├── element_renderer.ex                 # Renders each element type
│       ├── slash_command_menu.ex                # Command palette
│       ├── scene_heading_block.ex              # Scene heading element
│       ├── action_block.ex                     # Action element
│       ├── dialogue_group_block.ex             # Character + parenthetical + dialogue
│       ├── transition_block.ex                 # Transition element
│       ├── conditional_block.ex                # Condition block (wraps condition_builder)
│       ├── instruction_block.ex                # Instruction block (wraps instruction_builder)
│       ├── response_block.ex                   # Response choices block
│       ├── dual_dialogue_block.ex              # Side-by-side dialogue
│       ├── note_block.ex                       # Writer's note
│       └── page_break_block.ex                 # Page break

assets/js/
├── hooks/
│   ├── screenplay_editor.js                    # Main editor hook
│   ├── screenplay_element.js                   # Individual element hook
│   └── slash_command.js                        # Slash command detection + menu
├── screenplay/
│   ├── element_types.js                        # Element type registry
│   ├── keyboard_navigation.js                  # Arrow keys, Enter, Backspace between blocks
│   ├── formatting.js                           # CSS class computation per element type
│   └── auto_detect.js                          # Auto-detect element type from text patterns
```

---

## Phase 1: Database & Context

### 1.1 Migration: `create_screenplays`

```elixir
# priv/repo/migrations/TIMESTAMP_create_screenplays.exs

def change do
  create table(:screenplays) do
    add :name, :string, null: false
    add :shortcut, :string
    add :description, :string
    add :position, :integer, default: 0
    add :deleted_at, :utc_datetime

    # Relationships
    add :project_id, references(:projects, on_delete: :delete_all), null: false
    add :parent_id, references(:screenplays, on_delete: :nilify_all)
    add :linked_flow_id, references(:flows, on_delete: :nilify_all)

    # Draft support (see FUTURE_FEATURES.md — Copy-Based Drafts)
    # null = original, non-null = this is a draft of the referenced screenplay
    add :draft_of_id, references(:screenplays, on_delete: :delete_all)
    add :draft_label, :string           # "Alternative ending", "Draft B", etc.
    add :draft_status, :string, default: "active"  # "active" | "archived"

    timestamps(type: :utc_datetime)
  end

  create index(:screenplays, [:project_id])
  create index(:screenplays, [:parent_id])
  create index(:screenplays, [:project_id, :parent_id, :position])
  create index(:screenplays, [:deleted_at])
  create index(:screenplays, [:linked_flow_id])
  create index(:screenplays, [:draft_of_id])

  create unique_index(:screenplays, [:project_id, :shortcut],
    where: "shortcut IS NOT NULL AND deleted_at IS NULL",
    name: :screenplays_project_shortcut_unique
  )

  # Prevent multiple screenplays from linking to the same flow (Edge Case A)
  create unique_index(:screenplays, [:linked_flow_id],
    where: "linked_flow_id IS NOT NULL AND deleted_at IS NULL",
    name: :screenplays_linked_flow_unique
  )

  # -------------------------------------------------------

  create table(:screenplay_elements) do
    add :type, :string, null: false
    add :position, :integer, default: 0, null: false
    add :content, :text, default: ""
    add :data, :map, default: %{}
    add :depth, :integer, default: 0        # For nesting inside conditionals
    add :branch, :string                    # "true"/"false"/nil for conditional branches
    # NOTE: No group_id column — dialogue groups are computed from adjacency (Edge Case F)

    add :screenplay_id, references(:screenplays, on_delete: :delete_all), null: false
    add :linked_node_id, references(:flow_nodes, on_delete: :nilify_all)

    timestamps(type: :utc_datetime)
  end

  create index(:screenplay_elements, [:screenplay_id])
  create index(:screenplay_elements, [:screenplay_id, :position])
  create index(:screenplay_elements, [:linked_node_id])
end
```

### 1.2 Schemas

#### `Screenplay` schema (`lib/storyarn/screenplays/screenplay.ex`)

Follow the exact same pattern as `Flow` schema:

```elixir
defmodule Storyarn.Screenplays.Screenplay do
  use Ecto.Schema
  import Ecto.Changeset

  schema "screenplays" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :position, :integer, default: 0
    field :deleted_at, :utc_datetime

    # Draft support (see FUTURE_FEATURES.md — Copy-Based Drafts)
    field :draft_label, :string
    field :draft_status, :string, default: "active"

    belongs_to :project, Storyarn.Projects.Project
    belongs_to :parent, __MODULE__
    belongs_to :linked_flow, Storyarn.Flows.Flow
    belongs_to :draft_of, __MODULE__

    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :drafts, __MODULE__, foreign_key: :draft_of_id
    has_many :elements, Storyarn.Screenplays.ScreenplayElement

    timestamps(type: :utc_datetime)
  end

  def draft?(%__MODULE__{draft_of_id: id}), do: not is_nil(id)

  # Changesets: create, update, move, delete, restore, link_flow
  # Validation: same rules as Flow (name 1-200, shortcut regex, etc.)
end
```

#### `ScreenplayElement` schema (`lib/storyarn/screenplays/screenplay_element.ex`)

```elixir
defmodule Storyarn.Screenplays.ScreenplayElement do
  use Ecto.Schema
  import Ecto.Changeset

  @element_types ~w(
    scene_heading action character dialogue parenthetical
    transition dual_dialogue conditional instruction response
    hub_marker jump_marker
    note section page_break title_page
  )

  schema "screenplay_elements" do
    field :type, :string
    field :position, :integer, default: 0
    field :content, :string, default: ""
    field :data, :map, default: %{}
    field :depth, :integer, default: 0
    field :branch, :string
    # NOTE: No group_id — dialogue groups computed from adjacency (see Edge Case F)

    belongs_to :screenplay, Storyarn.Screenplays.Screenplay
    belongs_to :linked_node, Storyarn.Flows.FlowNode

    timestamps(type: :utc_datetime)
  end

  def types, do: @element_types

  # Standard screenplay element types (no flow mapping)
  def standard_types, do: ~w(scene_heading action character dialogue parenthetical transition dual_dialogue note section page_break title_page)

  # Interactive types (map to flow nodes)
  def interactive_types, do: ~w(conditional instruction response)

  # Flow navigation markers (round-trip safe, see Edge Case D)
  def flow_marker_types, do: ~w(hub_marker jump_marker)

  # Types that form dialogue groups (computed from adjacency)
  def dialogue_group_types, do: ~w(character dialogue parenthetical)

  # Types that have no flow mapping (preserved during sync_from_flow)
  def non_mappeable_types, do: ~w(note section page_break title_page)
end
```

### 1.3 Element Type Data Structures

Each element type uses the `content` field for its text and `data` for type-specific metadata:

```elixir
# scene_heading
%{type: "scene_heading", content: "INT. TAVERN - NIGHT", data: %{}}

# action
%{type: "action", content: "The door creaks open. JAIME enters.", data: %{}}

# character (dialogue groups computed from adjacency — no stored group_id)
%{type: "character", content: "JAIME", data: %{"sheet_id" => 42}}

# parenthetical (groups with adjacent character+dialogue automatically)
%{type: "parenthetical", content: "(looking around)", data: %{}}

# dialogue (groups with adjacent character+parenthetical automatically)
%{type: "dialogue", content: "Is anyone here?", data: %{}}

# transition
%{type: "transition", content: "CUT TO:", data: %{}}

# conditional — content is display label, data holds the condition
%{
  type: "conditional",
  content: "if mc.jaime.reputation > 5",
  data: %{
    "condition" => %{
      "logic" => "all",
      "rules" => [%{"sheet" => "mc.jaime", "variable" => "reputation", "operator" => "greater_than", "value" => "5"}]
    }
  }
}

# instruction — content is display label, data holds assignments
%{
  type: "instruction",
  content: "mc.jaime.visited_tavern = true",
  data: %{
    "assignments" => [%{"sheet" => "mc.jaime", "variable" => "visited_tavern", "operator" => "set_true"}]
  }
}

# response — each choice is an entry in data.choices
%{
  type: "response",
  content: "",
  data: %{
    "choices" => [
      %{
        "id" => "resp_1",
        "text" => "Pay for information",
        "condition" => %{"logic" => "all", "rules" => [...]},  # Optional
        "instruction" => [%{...}]                                # Optional
      },
      %{"id" => "resp_2", "text" => "Threaten the bartender"},
      %{"id" => "resp_3", "text" => "Leave"}
    ]
  }
}

# dual_dialogue — two speakers side by side
%{
  type: "dual_dialogue",
  content: "",
  data: %{
    "left" => %{
      "character" => "JAIME",
      "sheet_id" => 42,
      "parenthetical" => "(shouting)",
      "dialogue" => "Run!"
    },
    "right" => %{
      "character" => "BARTENDER",
      "sheet_id" => 55,
      "parenthetical" => nil,
      "dialogue" => "The back door!"
    }
  }
}

# hub_marker — preserves hub data for round-trip sync (Edge Case D)
%{type: "hub_marker", content: "Hub: Tavern Encounters", data: %{"hub_node_id" => 42, "color" => "blue"}}

# jump_marker — preserves jump target data for round-trip sync (Edge Case D)
%{type: "jump_marker", content: "-> Jump to: Tavern Encounters", data: %{"target_hub_id" => 42, "target_flow_id" => nil}}

# note
%{type: "note", content: "This scene needs more tension", data: %{}}

# section (outline headers, # = depth 1, ## = depth 2, ### = depth 3)
%{type: "section", content: "Act 1", data: %{"level" => 1}}

# page_break
%{type: "page_break", content: "", data: %{}}

# title_page
%{
  type: "title_page",
  content: "",
  data: %{
    "title" => "LA TABERNA DEL CUERVO",
    "credit" => "Written by",
    "author" => "Studio Dev",
    "draft_date" => "February 2026",
    "contact" => "studio@example.com"
  }
}
```

### 1.4 Context Facade (`lib/storyarn/screenplays.ex`)

Follow the same `defdelegate` pattern as `Sheets` and `Flows`:

```elixir
defmodule Storyarn.Screenplays do
  alias Storyarn.Screenplays.{
    Screenplay, ScreenplayElement,
    ScreenplayCrud, ElementCrud, ScreenplayQueries,
    TreeOperations, FlowSync, ElementGrouping
  }

  # Tree (excludes drafts — drafts are accessed via their original)
  defdelegate list_screenplays_tree(project_id), to: ScreenplayQueries
  defdelegate get_screenplay!(project_id, screenplay_id), to: ScreenplayCrud

  # CRUD
  defdelegate create_screenplay(project, attrs), to: ScreenplayCrud
  defdelegate update_screenplay(screenplay, attrs), to: ScreenplayCrud
  defdelegate delete_screenplay(screenplay), to: ScreenplayCrud
  defdelegate restore_screenplay(screenplay), to: ScreenplayCrud

  # Elements
  defdelegate list_elements(screenplay_id), to: ElementCrud
  defdelegate create_element(screenplay, attrs), to: ElementCrud
  defdelegate update_element(element, attrs), to: ElementCrud
  defdelegate delete_element(element), to: ElementCrud
  defdelegate reorder_elements(screenplay_id, element_ids), to: ElementCrud
  defdelegate insert_element_at(screenplay, position, attrs), to: ElementCrud
  defdelegate split_element(element, cursor_position, new_type), to: ElementCrud

  # Element grouping (computed, not stored — see Edge Case F)
  defdelegate compute_dialogue_groups(elements), to: ElementGrouping
  defdelegate group_elements(elements), to: ElementGrouping

  # Tree operations
  defdelegate move_screenplay_to_position(screenplay, parent_id, position), to: TreeOperations

  # Flow sync
  defdelegate sync_to_flow(screenplay), to: FlowSync
  defdelegate sync_from_flow(screenplay), to: FlowSync
  defdelegate link_to_flow(screenplay, flow_id), to: FlowSync
  defdelegate unlink_flow(screenplay), to: FlowSync
end
```

### 1.5 Submodules

#### `ScreenplayCrud` — CRUD operations

Copy the pattern from `Storyarn.Flows.FlowCrud`:
- `create_screenplay/2` — Creates screenplay with auto-assigned position, optionally inserts a default `title_page` element
- `update_screenplay/2` — Updates name, shortcut, description
- `delete_screenplay/1` — Soft delete (sets `deleted_at`)
- `restore_screenplay/1` — Clears `deleted_at`
- `get_screenplay!/2` — Fetch by project_id + screenplay_id, preload elements ordered by position

#### `ElementCrud` — Element operations

- `list_elements/1` — All elements for a screenplay ordered by position
- `create_element/2` — Append element at end
- `insert_element_at/3` — Insert at specific position, shift subsequent positions
- `update_element/2` — Update content/data/type
- `delete_element/1` — Remove and compact positions
- `reorder_elements/2` — Bulk reorder by list of IDs
- `split_element/3` — Split an element's content at cursor position, insert new element between halves. This is the core of the slash command system:
  1. Current element content is split at `cursor_position`
  2. Current element keeps text before cursor
  3. New element of `new_type` is inserted at `position + 1`
  4. A third element of original type is created at `position + 2` with text after cursor
  5. All subsequent elements shift by +2 positions

#### `ScreenplayQueries` — Read-only queries

- `list_screenplays_tree/1` — Tree structure for sidebar (same pattern as `Flows.list_flows_tree`). **Excludes drafts** (`WHERE draft_of_id IS NULL`).
- `get_with_elements/1` — Screenplay with all elements preloaded
- `count_elements/1` — Element count for badges
- `list_drafts/1` — List all drafts of a given screenplay (for the draft selector UI)

#### `TreeOperations` — Copy from `Storyarn.Flows.TreeOperations`

Identical logic: move screenplay within tree, reorder siblings, prevent cycles.

#### `ElementGrouping` — Group elements into flow-mappable units

```elixir
defmodule Storyarn.Screenplays.ElementGrouping do
  @doc """
  Groups consecutive elements into logical units that map to flow nodes.
  Dialogue groups are computed from adjacency — no stored group_id (Edge Case F).

  Rules:
  - Consecutive character + parenthetical? + dialogue (adjacent) → 1 Dialogue Node
  - scene_heading → Entry Node
  - transition → Exit Node / Connection
  - conditional → Condition Node (includes nested branch elements, depth support — Edge Case G)
  - instruction → Instruction Node
  - response → Adds responses to the preceding Dialogue Node (Edge Case E: orphan fallback)
  - action → Dialogue Node with empty text and stage_directions = content
  - dual_dialogue → Two parallel Dialogue Nodes (hub pattern)
  - hub_marker → Hub Node (round-trip safe — Edge Case D)
  - jump_marker → Jump Node (round-trip safe — Edge Case D)
  - note, section, page_break, title_page → No flow mapping (preserved on sync)
  """

  def group_elements(elements) do
    # Returns list of %ElementGroup{} structs
  end

  @doc """
  Computes dialogue groups from element adjacency.
  Returns elements annotated with a computed group identifier.

  Rules:
  - character starts a new group
  - parenthetical continues if preceded by character or dialogue in same group
  - dialogue continues if preceded by character or parenthetical in same group
  - any other type breaks the current group
  """
  def compute_dialogue_groups(elements) do
    # O(n) single-pass over elements list
  end
end
```

#### `FlowSync` — Bidirectional sync engine (Phase 6 & 7)

Detailed in Phase 6 and Phase 7 sections below.

---

## Phase 2: Sidebar & Navigation

### 2.1 Router

Add to `router.ex` alongside existing sheet/flow routes:

```elixir
# Screenplays
live "/workspaces/:workspace_slug/projects/:project_slug/screenplays",
     ScreenplayLive.Index, :index
live "/workspaces/:workspace_slug/projects/:project_slug/screenplays/:id",
     ScreenplayLive.Show, :show
```

### 2.2 Project Sidebar

Modify `lib/storyarn_web/components/project_sidebar.ex`:

1. Add `attr :screenplays_tree, :list, default: []`
2. Add `attr :selected_screenplay_id, :string, default: nil`
3. Extend `active_tool` atom to include `:screenplays`
4. Add third tree link under TOOLS section:

```heex
<.tree_link
  label={gettext("Screenplays")}
  icon="scroll-text"
  href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays"}
  active={@active_tool == :screenplays}
/>
```

5. Add conditional tree rendering:

```heex
<%= cond do %>
  <% @active_tool == :flows -> %>
    <FlowTree.flows_section ... />
  <% @active_tool == :screenplays -> %>
    <ScreenplayTree.screenplays_section ... />
  <% true -> %>
    <SheetTree.sheets_section ... />
<% end %>
```

### 2.3 Screenplay Tree Component

Create `lib/storyarn_web/components/sidebar/screenplay_tree.ex`:

Copy the exact structure of `flow_tree.ex` but for screenplays. Uses the same `<.tree_node>` and `<.tree_leaf>` components. Context menu actions:
- Rename
- Duplicate
- Move to...
- Link to Flow... (opens flow selector modal)
- Unlink Flow
- Delete

Icon for screenplays in tree: `"scroll-text"` (Lucide icon).

### 2.4 LiveView: `ScreenplayLive.Index`

Copy pattern from `FlowLive.Index`:

```elixir
defmodule StoryarnWeb.ScreenplayLive.Index do
  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Screenplays

  def mount(%{"workspace_slug" => ws_slug, "project_slug" => p_slug}, _session, socket) do
    # Same pattern as FlowLive.Index:
    # 1. Get project + membership
    # 2. Load screenplays_tree
    # 3. Assign to socket with active_tool: :screenplays
  end

  def render(assigns) do
    ~H"""
    <Layouts.project
      ...
      screenplays_tree={@screenplays_tree}
      active_tool={:screenplays}
      selected_screenplay_id={nil}
    >
      <!-- Index content: list of screenplays as cards or empty state -->
    </Layouts.project>
    """
  end

  # Events: create_screenplay, delete_screenplay, move_to_parent, rename_screenplay
end
```

### 2.5 Layout Integration

Modify `Layouts.project` to accept and pass through:
- `screenplays_tree` attr
- `selected_screenplay_id` attr
- These get forwarded to `project_sidebar`

### 2.6 Gettext

Add translations for all new user-facing strings:
- `gettext("Screenplays")` — sidebar label
- `gettext("New Screenplay")` — create button
- `gettext("Untitled Screenplay")` — default name
- All element type labels, slash command descriptions

---

## Phase 3: Screenplay Editor (Core Blocks)

> **Note:** This phase includes collaboration setup (Edge Case H). Element locking and
> presence tracking are built into the editor from the start, not added later.

### 3.1 LiveView: `ScreenplayLive.Show`

The main editor view. This is the most complex part.

```elixir
defmodule StoryarnWeb.ScreenplayLive.Show do
  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.{Screenplays, Collaboration}

  def mount(params, _session, socket) do
    screenplay = Screenplays.get_screenplay!(project.id, params["id"])
    elements = Screenplays.list_elements(screenplay.id)
    project_variables = Sheets.list_project_variables(project.id)
    all_sheets = Sheets.list_sheets_flat(project.id)  # For speaker selection

    # Check linked flow status (Edge Case I)
    link_status = check_link_status(screenplay)

    # Setup collaboration: presence + element locks + change broadcasts (Edge Case H)
    # Uses topic "screenplay:{id}" — same Collaboration module as flows
    socket = CollaborationHelpers.setup_screenplay_collaboration(socket, screenplay, current_user)

    socket
    |> assign(:screenplay, screenplay)
    |> assign(:elements, elements)
    |> assign(:project_variables, project_variables)
    |> assign(:all_sheets, all_sheets)
    |> assign(:focused_element_id, nil)
    |> assign(:editing_element_id, nil)
    |> assign(:link_status, link_status)          # Edge Case I
    |> assign(:undo_stack, [])                    # Edge Case J (structural undo)
    |> assign(:redo_stack, [])                    # Edge Case J (structural redo)
  end

  def render(assigns) do
    ~H"""
    <Layouts.project ... active_tool={:screenplays} selected_screenplay_id={to_string(@screenplay.id)}>
      <div class="screenplay-editor-container">
        <!-- Toolbar: screenplay name, link status, export button -->
        <.screenplay_toolbar screenplay={@screenplay} />

        <!-- The screenplay "page" -->
        <div class="screenplay-page" id="screenplay-page" phx-hook="ScreenplayEditor">
          <.element_renderer
            :for={element <- @elements}
            element={element}
            focused={element.id == @focused_element_id}
            can_edit={@can_edit}
            all_sheets={@all_sheets}
            project_variables={@project_variables}
          />

          <!-- Empty state / add first element -->
          <div :if={@elements == []} class="screenplay-empty-state">
            <%= gettext("Start typing or press / for commands") %>
          </div>
        </div>
      </div>
    </Layouts.project>
    """
  end
end
```

### 3.2 Screenplay Page Styling

The editor renders elements inside a page-like container:

```css
/* Screenplay page container */
.screenplay-page {
  max-width: 816px;           /* 8.5 inches at 96dpi */
  margin: 0 auto;
  padding: 96px 96px 96px 144px; /* top 1", right 1", bottom 1", left 1.5" */
  background: white;
  font-family: "Courier New", Courier, monospace;
  font-size: 12pt;
  line-height: 1.0;           /* Single-spaced */
  color: #1a1a1a;
  min-height: 1056px;         /* 11 inches */
  box-shadow: 0 2px 8px rgba(0,0,0,0.15);
}

/* Dark mode: invert page */
[data-theme="dark"] .screenplay-page {
  background: #1d232a;
  color: #e0e0e0;
}
```

### 3.3 Element CSS (per type)

Each element type has specific indentation and formatting:

```css
/* Scene Heading: full width, ALL CAPS, bold */
.sp-scene-heading {
  text-transform: uppercase;
  font-weight: bold;
  margin-top: 24px;           /* Two blank lines before */
  margin-bottom: 12px;        /* One blank line after */
}

/* Action: full width, normal case */
.sp-action {
  margin-top: 12px;
  margin-bottom: 12px;
}

/* Character: centered, ALL CAPS */
.sp-character {
  text-transform: uppercase;
  margin-left: 192px;         /* ~2.2" additional from left margin → 3.7" total */
  margin-top: 12px;
  margin-bottom: 0;
}

/* Parenthetical: indented, in parentheses */
.sp-parenthetical {
  margin-left: 144px;         /* ~1.5" additional → 3.1" total */
  max-width: 192px;           /* ~2" wide */
  margin-top: 0;
  margin-bottom: 0;
}

/* Dialogue: indented, narrower */
.sp-dialogue {
  margin-left: 96px;          /* ~1" additional → 2.5" total */
  max-width: 288px;           /* ~3" wide */
  margin-top: 0;
  margin-bottom: 0;
}

/* Transition: right-aligned, ALL CAPS */
.sp-transition {
  text-align: right;
  text-transform: uppercase;
  margin-top: 12px;
  margin-bottom: 12px;
}

/* Dual dialogue: two columns */
.sp-dual-dialogue {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
  margin-top: 12px;
  margin-bottom: 12px;
}

/* Note: styled distinctly (not screenplay format) */
.sp-note {
  background: oklch(0.95 0.02 90);
  border-left: 3px solid oklch(0.7 0.15 90);
  padding: 8px 12px;
  font-family: sans-serif;
  font-size: 0.85rem;
  color: oklch(0.4 0.05 90);
  margin: 12px 0;
}

/* Interactive blocks: distinct visual treatment */
.sp-conditional,
.sp-instruction,
.sp-response {
  font-family: sans-serif;
  font-size: 0.85rem;
  border: 1px solid oklch(0.8 0.02 250);
  border-radius: 8px;
  padding: 12px 16px;
  margin: 16px 0;
  background: oklch(0.97 0.005 250);
}

.sp-conditional {
  border-color: oklch(0.7 0.15 280);
  background: oklch(0.97 0.02 280);
}

.sp-instruction {
  border-color: oklch(0.7 0.15 50);
  background: oklch(0.97 0.02 50);
}

.sp-response {
  border-color: oklch(0.7 0.15 150);
  background: oklch(0.97 0.02 150);
}

/* Section headers (outline, not rendered in export) */
.sp-section {
  font-family: sans-serif;
  font-weight: bold;
  color: oklch(0.5 0.1 250);
  border-bottom: 1px solid oklch(0.85 0.02 250);
  padding-bottom: 4px;
  margin: 24px 0 12px;
}

/* Page break */
.sp-page-break {
  border-top: 2px dashed oklch(0.8 0 0);
  margin: 24px 0;
  text-align: center;
  color: oklch(0.6 0 0);
  font-size: 0.75rem;
}
```

### 3.4 Element Renderer Component

`lib/storyarn_web/components/screenplay/element_renderer.ex`:

A single component that dispatches to the correct block renderer based on element type:

```elixir
defmodule StoryarnWeb.Components.Screenplay.ElementRenderer do
  use StoryarnWeb, :component

  attr :element, :map, required: true
  attr :focused, :boolean, default: false
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :project_variables, :list, default: []

  def element_renderer(assigns) do
    ~H"""
    <div
      class={["screenplay-element", "sp-#{@element.type}", @focused && "sp-focused"]}
      id={"sp-el-#{@element.id}"}
      data-element-id={@element.id}
      data-element-type={@element.type}
      data-position={@element.position}
      phx-click="focus_element"
      phx-value-id={@element.id}
    >
      <%= case @element.type do %>
        <% "scene_heading" -> %> <.scene_heading_block element={@element} can_edit={@can_edit} />
        <% "action" -> %>        <.action_block element={@element} can_edit={@can_edit} />
        <% "character" -> %>     <.character_block element={@element} can_edit={@can_edit} all_sheets={@all_sheets} />
        <% "dialogue" -> %>      <.dialogue_block element={@element} can_edit={@can_edit} />
        <% "parenthetical" -> %> <.parenthetical_block element={@element} can_edit={@can_edit} />
        <% "transition" -> %>    <.transition_block element={@element} can_edit={@can_edit} />
        <% "conditional" -> %>   <.conditional_block element={@element} can_edit={@can_edit} project_variables={@project_variables} />
        <% "instruction" -> %>   <.instruction_block element={@element} can_edit={@can_edit} project_variables={@project_variables} />
        <% "response" -> %>      <.response_block element={@element} can_edit={@can_edit} project_variables={@project_variables} />
        <% "dual_dialogue" -> %> <.dual_dialogue_block element={@element} can_edit={@can_edit} all_sheets={@all_sheets} />
        <% "note" -> %>          <.note_block element={@element} can_edit={@can_edit} />
        <% "section" -> %>       <.section_block element={@element} can_edit={@can_edit} />
        <% "page_break" -> %>    <.page_break_block />
        <% "title_page" -> %>    <.title_page_block element={@element} can_edit={@can_edit} />
      <% end %>
    </div>
    """
  end
end
```

### 3.5 Standard Block Components (text-based)

Each standard block is a `contenteditable` div or input that:
- Renders with correct CSS class
- Sends content changes via `phx-hook` on blur/debounce
- Handles Enter to create next element
- Handles Backspace at start to merge with previous or delete empty

Example for `scene_heading_block`:

```elixir
def scene_heading_block(assigns) do
  ~H"""
  <div
    contenteditable={to_string(@can_edit)}
    phx-hook="ScreenplayElement"
    id={"sp-edit-#{@element.id}"}
    data-element-id={@element.id}
    data-element-type="scene_heading"
    class="sp-scene-heading-input outline-none"
    data-placeholder={gettext("INT. LOCATION - TIME")}
    phx-update="ignore"
  ><%= @element.content %></div>
  """
end
```

### 3.6 JS Hook: `ScreenplayElement`

Each element's `contenteditable` area is managed by this hook:

```javascript
// assets/js/hooks/screenplay_element.js

export const ScreenplayElement = {
  mounted() {
    this.elementId = this.el.dataset.elementId;
    this.elementType = this.el.dataset.elementType;
    this.debounceTimer = null;

    // Show placeholder when empty
    this.updatePlaceholder();

    // Content change (debounced)
    this.el.addEventListener("input", () => {
      this.updatePlaceholder();
      clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => {
        this.pushEvent("update_element_content", {
          id: this.elementId,
          content: this.el.textContent
        });
      }, 500);
    });

    // Keyboard navigation
    this.el.addEventListener("keydown", (e) => this.handleKeydown(e));
  },

  handleKeydown(e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      // Determine next element type based on current:
      // scene_heading → action
      // character → dialogue (or parenthetical if typed "(")
      // dialogue → character (new speaker) or action
      // parenthetical → dialogue
      // action → action (or character if ALL CAPS detected)
      const nextType = this.inferNextType();
      this.pushEvent("create_next_element", {
        after_id: this.elementId,
        type: nextType,
        content: ""
      });
    }

    if (e.key === "Backspace" && this.isAtStart()) {
      if (this.el.textContent === "") {
        e.preventDefault();
        this.pushEvent("delete_element", { id: this.elementId });
      }
    }

    // Slash command detection
    if (e.key === "/" && this.el.textContent === "") {
      e.preventDefault();
      this.pushEvent("open_slash_menu", {
        element_id: this.elementId,
        position: this.getPosition()
      });
    }

    // Tab to change element type
    if (e.key === "Tab") {
      e.preventDefault();
      const types = ["action", "scene_heading", "character", "dialogue", "parenthetical", "transition"];
      const currentIdx = types.indexOf(this.elementType);
      const nextIdx = e.shiftKey
        ? (currentIdx - 1 + types.length) % types.length
        : (currentIdx + 1) % types.length;
      this.pushEvent("change_element_type", {
        id: this.elementId,
        type: types[nextIdx]
      });
    }
  },

  inferNextType() {
    // Standard screenplay flow:
    const transitions = {
      scene_heading: "action",
      action: "character",
      character: "dialogue",
      parenthetical: "dialogue",
      dialogue: "character",
      transition: "scene_heading"
    };
    return transitions[this.elementType] || "action";
  },

  isAtStart() {
    const sel = window.getSelection();
    return sel.anchorOffset === 0 && sel.focusOffset === 0;
  },

  updatePlaceholder() {
    if (this.el.textContent.trim() === "") {
      this.el.classList.add("sp-empty");
    } else {
      this.el.classList.remove("sp-empty");
    }
  }
};
```

### 3.7 JS Hook: `ScreenplayEditor`

Orchestrator hook on the page container:

```javascript
// assets/js/hooks/screenplay_editor.js

export const ScreenplayEditor = {
  mounted() {
    // Handle arrow key navigation between elements
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "ArrowUp" || e.key === "ArrowDown") {
        this.handleArrowNavigation(e);
      }
    });

    // Focus management: after LiveView patch, re-focus the right element
    this.handleEvent("focus_element", ({ id }) => {
      requestAnimationFrame(() => {
        const el = document.getElementById(`sp-edit-${id}`);
        if (el) {
          el.focus();
          // Place cursor at end
          const range = document.createRange();
          const sel = window.getSelection();
          range.selectNodeContents(el);
          range.collapse(false);
          sel.removeAllRanges();
          sel.addRange(range);
        }
      });
    });
  },

  handleArrowNavigation(e) {
    // Move focus to previous/next element when at top/bottom of current
    const elements = this.el.querySelectorAll("[contenteditable]");
    const active = document.activeElement;
    const idx = Array.from(elements).indexOf(active);

    if (e.key === "ArrowUp" && idx > 0 && this.isAtFirstLine(active)) {
      e.preventDefault();
      elements[idx - 1].focus();
    }
    if (e.key === "ArrowDown" && idx < elements.length - 1 && this.isAtLastLine(active)) {
      e.preventDefault();
      elements[idx + 1].focus();
    }
  }
};
```

### 3.8 LiveView Event Handlers

In `ScreenplayLive.Show`:

```elixir
# Update element content (debounced from JS)
def handle_event("update_element_content", %{"id" => id, "content" => content}, socket) do
  element = get_element(socket, id)
  {:ok, updated} = Screenplays.update_element(element, %{content: content})
  {:noreply, update_element_in_list(socket, updated)}
end

# Create next element after current
def handle_event("create_next_element", %{"after_id" => after_id, "type" => type, "content" => content}, socket) do
  element = get_element(socket, after_id)
  {:ok, new_element} = Screenplays.insert_element_at(
    socket.assigns.screenplay,
    element.position + 1,
    %{type: type, content: content}
  )
  elements = Screenplays.list_elements(socket.assigns.screenplay.id)

  socket
  |> assign(:elements, elements)
  |> push_event("focus_element", %{id: new_element.id})
  |> then(&{:noreply, &1})
end

# Delete element
def handle_event("delete_element", %{"id" => id}, socket) do
  element = get_element(socket, id)
  prev_element = get_previous_element(socket, element.position)
  {:ok, _} = Screenplays.delete_element(element)
  elements = Screenplays.list_elements(socket.assigns.screenplay.id)

  socket
  |> assign(:elements, elements)
  |> then(fn s ->
    if prev_element, do: push_event(s, "focus_element", %{id: prev_element.id}), else: s
  end)
  |> then(&{:noreply, &1})
end

# Change element type (Tab key)
def handle_event("change_element_type", %{"id" => id, "type" => new_type}, socket) do
  element = get_element(socket, id)
  {:ok, updated} = Screenplays.update_element(element, %{type: new_type})
  {:noreply, update_element_in_list(socket, updated)}
end
```

### 3.9 Auto-Detection

Some element types can be auto-detected from text patterns:

```elixir
# In ElementCrud or a helper module
def auto_detect_type(content) do
  trimmed = String.trim(content)
  cond do
    # Scene heading: starts with INT. or EXT. (or variants)
    trimmed =~ ~r/^(INT\.|EXT\.|INT\.\/EXT\.|I\/E\.?)\s/i -> "scene_heading"

    # Transition: ALL CAPS ending in "TO:" or specific keywords
    trimmed =~ ~r/^[A-Z\s]+TO:$/ -> "transition"
    trimmed in ["FADE IN:", "FADE OUT.", "FADE TO BLACK."] -> "transition"

    # Character: ALL CAPS with optional (V.O.), (O.S.), (CONT'D)
    trimmed =~ ~r/^[A-Z][A-Z\s\.']+(\s*\([\w\.]+\))?$/ and String.length(trimmed) < 50 ->
      "character"

    # Parenthetical: starts and ends with parentheses
    trimmed =~ ~r/^\(.*\)$/ -> "parenthetical"

    # Default: action
    true -> "action"
  end
end
```

---

## Phase 4: Slash Command System

### 4.1 Slash Command Menu Component

When user types `/` in an empty element, show a floating command palette:

```elixir
# lib/storyarn_web/components/screenplay/slash_command_menu.ex

defmodule StoryarnWeb.Components.Screenplay.SlashCommandMenu do
  use StoryarnWeb, :component

  def slash_command_menu(assigns) do
    ~H"""
    <div
      id="slash-command-menu"
      class="slash-menu"
      phx-hook="SlashCommand"
      data-element-id={@element_id}
      style={"top: #{@position.top}px; left: #{@position.left}px"}
    >
      <div class="slash-menu-search">
        <input type="text" placeholder={gettext("Filter commands...")} autofocus />
      </div>
      <div class="slash-menu-list">
        <!-- Standard screenplay elements -->
        <.slash_group label={gettext("Screenplay")}>
          <.slash_item type="scene_heading" icon="clapperboard" label={gettext("Scene Heading")} description={gettext("INT./EXT. Location - Time")} />
          <.slash_item type="action" icon="align-left" label={gettext("Action")} description={gettext("Narrative description")} />
          <.slash_item type="character" icon="user" label={gettext("Character")} description={gettext("Character name (ALL CAPS)")} />
          <.slash_item type="dialogue" icon="message-square" label={gettext("Dialogue")} description={gettext("Spoken text")} />
          <.slash_item type="parenthetical" icon="parentheses" label={gettext("Parenthetical")} description={gettext("(acting direction)")} />
          <.slash_item type="transition" icon="arrow-right" label={gettext("Transition")} description={gettext("CUT TO:, FADE IN:")} />
          <.slash_item type="dual_dialogue" icon="columns-2" label={gettext("Dual Dialogue")} description={gettext("Two speakers simultaneously")} />
        </.slash_group>

        <!-- Interactive/game elements -->
        <.slash_group label={gettext("Interactive")}>
          <.slash_item type="conditional" icon="git-branch" label={gettext("Condition")} description={gettext("Branch based on variable")} />
          <.slash_item type="instruction" icon="zap" label={gettext("Instruction")} description={gettext("Modify a variable")} />
          <.slash_item type="response" icon="list" label={gettext("Responses")} description={gettext("Player choices")} />
        </.slash_group>

        <!-- Utility elements -->
        <.slash_group label={gettext("Utility")}>
          <.slash_item type="note" icon="sticky-note" label={gettext("Note")} description={gettext("Writer's note (not exported)")} />
          <.slash_item type="section" icon="heading" label={gettext("Section")} description={gettext("Outline header")} />
          <.slash_item type="page_break" icon="scissors" label={gettext("Page Break")} description={gettext("Force page break")} />
        </.slash_group>
      </div>
    </div>
    """
  end
end
```

### 4.2 Slash Command Behavior

When a slash command is selected:

1. **If current element is empty**: Replace current element's type with selected type
2. **If current element has content**: Split at cursor position:
   - Text before cursor stays in current element
   - New element of selected type inserted after
   - Text after cursor goes into a third element (same type as original)
3. **For interactive types** (`conditional`, `instruction`, `response`): Open the respective builder UI inline

### 4.3 Handling `/` Mid-Text

When the user types `/` inside a non-empty element:

```javascript
// In screenplay_element.js keydown handler
if (e.key === "/" && e.target.textContent.trim() !== "") {
  // Check if "/" is being typed at a natural break point
  const text = e.target.textContent;
  const cursorPos = window.getSelection().anchorOffset;
  const beforeCursor = text.substring(0, cursorPos);

  // Only trigger slash menu if "/" is at start of a new line or after empty space
  if (beforeCursor.endsWith("\n") || beforeCursor === "" || beforeCursor.endsWith(" ")) {
    e.preventDefault();
    this.pushEvent("split_and_open_slash_menu", {
      element_id: this.elementId,
      cursor_position: cursorPos
    });
  }
  // Otherwise, let "/" be typed normally
}
```

### 4.4 LiveView Handler for Split

```elixir
def handle_event("split_and_open_slash_menu", %{"element_id" => id, "cursor_position" => pos}, socket) do
  element = get_element(socket, id)
  # Split content at cursor position
  {:ok, _before, new_element, _after} = Screenplays.split_element(element, pos, "action")
  elements = Screenplays.list_elements(socket.assigns.screenplay.id)

  socket
  |> assign(:elements, elements)
  |> assign(:slash_menu_element_id, new_element.id)
  |> then(&{:noreply, &1})
end

def handle_event("select_slash_command", %{"element_id" => id, "type" => type}, socket) do
  element = get_element(socket, id)
  {:ok, updated} = Screenplays.update_element(element, %{type: type})
  elements = Screenplays.list_elements(socket.assigns.screenplay.id)

  socket
  |> assign(:elements, elements)
  |> assign(:slash_menu_element_id, nil)
  |> push_event("focus_element", %{id: updated.id})
  |> then(&{:noreply, &1})
end
```

---

## Phase 5: Interactive Blocks (Condition/Instruction/Response)

### 5.1 Conditional Block

Renders inline within the screenplay. Uses the existing `ConditionBuilder` component.

```elixir
def conditional_block(assigns) do
  ~H"""
  <div class="sp-conditional-wrapper">
    <div class="sp-block-header">
      <.icon name="git-branch" class="size-4" />
      <span class="sp-block-label"><%= gettext("Condition") %></span>
      <button phx-click="delete_element" phx-value-id={@element.id} class="sp-block-delete">
        <.icon name="x" class="size-3" />
      </button>
    </div>

    <!-- Condition builder (reuses existing component) -->
    <.condition_builder
      id={"sp-cond-#{@element.id}"}
      condition={@element.data["condition"]}
      variables={@project_variables}
      can_edit={@can_edit}
      switch_mode={false}
      context={%{"element-id" => @element.id}}
    />

    <!-- Branch containers for nested elements -->
    <div class="sp-branches">
      <div class="sp-branch sp-branch-true">
        <div class="sp-branch-label"><%= gettext("True") %></div>
        <div class="sp-branch-content" data-branch="true" data-depth={@element.depth + 1}>
          <!-- Nested elements with branch="true" rendered here -->
        </div>
      </div>
      <div class="sp-branch sp-branch-false">
        <div class="sp-branch-label"><%= gettext("False") %></div>
        <div class="sp-branch-content" data-branch="false" data-depth={@element.depth + 1}>
          <!-- Nested elements with branch="false" rendered here -->
        </div>
      </div>
    </div>
  </div>
  """
end
```

### 5.2 Conditional Branching Model

When a conditional block is created, elements inside it belong to a **branch**:

```
Element List (flat, ordered by position):
┌──────────────────────────────────────────────────┐
│ pos=0  type=scene_heading   depth=0  branch=nil  │
│ pos=1  type=action          depth=0  branch=nil  │
│ pos=2  type=character       depth=0  branch=nil  │
│ pos=3  type=dialogue        depth=0  branch=nil  │
│ pos=4  type=conditional     depth=0  branch=nil  │  ← CONDITION
│ pos=5  type=character       depth=1  branch=true │  ← Inside TRUE
│ pos=6  type=dialogue        depth=1  branch=true │
│ pos=7  type=character       depth=1  branch=false│  ← Inside FALSE
│ pos=8  type=dialogue        depth=1  branch=false│
│ pos=9  type=character       depth=0  branch=nil  │  ← After condition
│ pos=10 type=dialogue        depth=0  branch=nil  │
└──────────────────────────────────────────────────┘
```

The `depth` and `branch` fields determine rendering:
- `depth=0, branch=nil` → rendered at root level
- `depth=1, branch="true"` → rendered inside the TRUE branch of the nearest conditional at depth=0
- `depth=1, branch="false"` → rendered inside the FALSE branch

The rendering logic in the LiveView groups elements by their conditional context before passing to the template.

### 5.3 Instruction Block

```elixir
def instruction_block(assigns) do
  ~H"""
  <div class="sp-instruction-wrapper">
    <div class="sp-block-header">
      <.icon name="zap" class="size-4" />
      <span class="sp-block-label"><%= gettext("Instruction") %></span>
      <button phx-click="delete_element" phx-value-id={@element.id} class="sp-block-delete">
        <.icon name="x" class="size-3" />
      </button>
    </div>

    <!-- Instruction builder (reuses existing component) -->
    <.instruction_builder
      id={"sp-instr-#{@element.id}"}
      assignments={@element.data["assignments"] || []}
      variables={@project_variables}
      can_edit={@can_edit}
    />
  </div>
  """
end
```

### 5.4 Response Block

```elixir
def response_block(assigns) do
  ~H"""
  <div class="sp-response-wrapper">
    <div class="sp-block-header">
      <.icon name="list" class="size-4" />
      <span class="sp-block-label"><%= gettext("Responses") %></span>
    </div>

    <div class="sp-response-list">
      <div :for={choice <- (@element.data["choices"] || [])} class="sp-response-item">
        <span class="sp-response-arrow">→</span>
        <input
          type="text"
          value={choice["text"]}
          placeholder={gettext("Response text...")}
          phx-blur="update_response_text"
          phx-value-element-id={@element.id}
          phx-value-choice-id={choice["id"]}
          class="sp-response-input"
        />

        <!-- Optional condition indicator -->
        <span :if={choice["condition"]} class="sp-response-indicator" title={gettext("Has condition")}>
          [?]
        </span>

        <!-- Optional instruction indicator -->
        <span :if={choice["instruction"]} class="sp-response-indicator" title={gettext("Has instruction")}>
          [⚡]
        </span>

        <!-- Expand button to edit condition/instruction -->
        <button phx-click="toggle_response_detail" phx-value-choice-id={choice["id"]}>
          <.icon name="chevron-down" class="size-3" />
        </button>
      </div>

      <button :if={@can_edit} phx-click="add_response_choice" phx-value-element-id={@element.id}
              class="sp-add-response">
        + <%= gettext("Add response") %>
      </button>
    </div>
  </div>
  """
end
```

### 5.5 Event Handlers for Interactive Blocks

```elixir
# Condition builder update (from ConditionBuilder hook)
def handle_event("update_condition_builder", %{"condition" => condition, "element-id" => element_id}, socket) do
  element = get_element(socket, element_id)
  sanitized = Condition.sanitize(condition)
  {:ok, updated} = Screenplays.update_element(element, %{
    data: Map.put(element.data, "condition", sanitized),
    content: Condition.format_short(sanitized)  # Human-readable label
  })
  {:noreply, update_element_in_list(socket, updated)}
end

# Instruction builder update (from InstructionBuilder hook)
def handle_event("update_instruction_builder", %{"assignments" => assignments, "element-id" => element_id}, socket) do
  element = get_element(socket, element_id)
  sanitized = Instruction.sanitize(assignments)
  {:ok, updated} = Screenplays.update_element(element, %{
    data: Map.put(element.data, "assignments", sanitized),
    content: Instruction.format_assignments_short(sanitized)
  })
  {:noreply, update_element_in_list(socket, updated)}
end

# Response management
def handle_event("add_response_choice", %{"element-id" => element_id}, socket) do
  element = get_element(socket, element_id)
  choices = element.data["choices"] || []
  new_choice = %{"id" => Ecto.UUID.generate(), "text" => "", "condition" => nil, "instruction" => nil}
  {:ok, updated} = Screenplays.update_element(element, %{
    data: Map.put(element.data, "choices", choices ++ [new_choice])
  })
  {:noreply, update_element_in_list(socket, updated)}
end
```

---

## Phase 6: Flow Sync — Screenplay → Flow

### 6.1 Sync Strategy

When a screenplay is linked to a flow (or a new flow is created from a screenplay), the sync engine:

1. Groups screenplay elements into logical units via `ElementGrouping`
2. Creates/updates flow nodes for each group
3. Creates connections based on element order
4. Stores `linked_node_id` on each element for tracking

### 6.2 Element → Node Mapping

```
Screenplay Element(s)           →  Flow Node Type
─────────────────────────────────────────────────
scene_heading                   →  entry
character + parenthetical? +    →  dialogue (speaker_sheet_id from character.data.sheet_id,
  dialogue (adjacent group)        stage_directions from parenthetical, text from dialogue)
action                          →  dialogue (text="", stage_directions=content)
conditional                     →  condition (expression from data.condition)
instruction                     →  instruction (assignments from data.assignments)
response                        →  Adds responses[] to PREVIOUS dialogue node
                                   (orphan fallback: auto-wraps in empty dialogue — Edge Case E)
transition                      →  exit
dual_dialogue                   →  Two dialogue nodes in parallel (hub pattern)
hub_marker                      →  hub (data preserved for round-trip — Edge Case D)
jump_marker                     →  jump (data preserved for round-trip — Edge Case D)
note, section, page_break       →  No mapping (preserved during sync — Edge Case C)
title_page                      →  No mapping (preserved during sync — Edge Case C)
```

### 6.3 FlowSync Module

```elixir
defmodule Storyarn.Screenplays.FlowSync do
  alias Storyarn.{Flows, Screenplays}

  @doc """
  Sync screenplay content to its linked flow using diff-based approach (Edge Case C).
  Creates the flow if it doesn't exist.
  Preserves manually-added nodes (source="manual") and node canvas positions.
  """
  def sync_to_flow(%Screenplay{} = screenplay) do
    elements = Screenplays.list_elements(screenplay.id)
    groups = ElementGrouping.group_elements(elements)

    flow = ensure_flow(screenplay)

    Repo.transaction(fn ->
      # 1. Load existing synced nodes (source="screenplay_sync") — Edge Case B
      existing_synced = load_synced_nodes(flow)
      existing_map = Map.new(existing_synced, &{&1.id, &1})

      # 2. Diff: create new, update changed, delete removed (preserve XY positions)
      {nodes, element_node_map} = diff_and_apply_nodes(flow, groups, existing_map)

      # 3. Update connections (sequential order, branching for conditionals)
      update_connections(flow, nodes, groups)

      # 4. Update linked_node_id on elements
      update_element_links(element_node_map)

      # 5. Auto-layout ONLY new nodes (existing keep their positions)
      auto_layout_new_nodes(flow, nodes, existing_map)
    end)
  end

  @doc """
  Link a screenplay to an existing flow.
  """
  def link_to_flow(%Screenplay{} = screenplay, flow_id) do
    screenplay
    |> Screenplay.link_flow_changeset(%{linked_flow_id: flow_id})
    |> Repo.update()
  end

  @doc """
  Unlink a screenplay from its flow. Does NOT delete the flow.
  Clears linked_node_id from all elements.
  """
  def unlink_flow(%Screenplay{} = screenplay) do
    Repo.transaction(fn ->
      # Clear all element links
      from(e in ScreenplayElement,
        where: e.screenplay_id == ^screenplay.id and not is_nil(e.linked_node_id)
      )
      |> Repo.update_all(set: [linked_node_id: nil])

      # Unlink screenplay
      screenplay
      |> Screenplay.link_flow_changeset(%{linked_flow_id: nil})
      |> Repo.update!()
    end)
  end

  defp ensure_flow(%Screenplay{linked_flow_id: nil} = screenplay) do
    {:ok, flow} = Flows.create_flow(screenplay.project_id, %{
      name: screenplay.name <> " (Flow)",
      description: "Auto-generated from screenplay"
    })
    link_to_flow(screenplay, flow.id)
    flow
  end
  defp ensure_flow(%Screenplay{linked_flow_id: flow_id}) do
    Flows.get_flow!(flow_id)
  end
end
```

### 6.4 Auto-Layout Algorithm

When generating a flow from screenplay, nodes need positions:

```elixir
defp auto_layout_nodes(flow, nodes) do
  # Simple vertical layout:
  # - Sequential nodes: stack vertically with 150px spacing
  # - Conditional branches: offset horizontally
  #   TRUE branch: x - 200
  #   FALSE branch: x + 200
  # - After condition merge: return to center x
  # Base position: x=400, y=100
  # Increment y by 150 for each node

  x_center = 400
  y_start = 100
  y_spacing = 150
  branch_offset = 250

  # Walk through nodes and assign positions
  # (detailed algorithm handles nested conditionals)
end
```

### 6.5 When to Sync

Sync is triggered:
- **Manually**: User clicks "Sync to Flow" button in toolbar
- **On save**: Optionally, debounced auto-sync (user preference)
- **On link**: When linking screenplay to a flow for the first time

Important: Do NOT sync on every keystroke. Sync is a batch operation.

---

## Phase 7: Flow Sync — Flow → Screenplay

### 7.1 Strategy

When a flow exists and a screenplay is created from it (or the flow is edited while linked):

1. DFS traversal from entry node(s)
2. Each node generates screenplay elements
3. Branches in the flow create conditional blocks in the screenplay
4. Connections define element order

### 7.2 Node → Element Mapping

```
Flow Node Type    →  Screenplay Element(s)
───────────────────────────────────────────
entry             →  scene_heading (name from node label)
dialogue          →  character + parenthetical? + dialogue
                     (+ response block if node has responses)
condition         →  conditional block
                     (nested elements for true/false branches — Edge Case G)
instruction       →  instruction block
hub               →  hub_marker (preserves all hub data — Edge Case D)
jump              →  jump_marker (preserves all jump data — Edge Case D)
exit              →  transition
```

### 7.3 FlowSync.sync_from_flow

```elixir
@doc """
Sync flow content to screenplay using diff-based approach (Edge Case C).
Preserves non-mappeable elements (notes, sections, page_breaks, title_page).
"""
def sync_from_flow(%Screenplay{linked_flow_id: flow_id} = screenplay) when not is_nil(flow_id) do
  flow = Flows.get_flow_with_nodes_and_connections!(flow_id)
  all_sheets = Sheets.list_sheets_flat(screenplay.project_id)

  Repo.transaction(fn ->
    # 1. Load existing elements, separate mappeable from non-mappeable
    existing = Screenplays.list_elements(screenplay.id)
    {mappeable, preserved} = split_by_mappeability(existing)
    existing_map = Map.new(mappeable, &{&1.linked_node_id, &1})

    # 2. Find entry nodes (starting points)
    entry_nodes = Enum.filter(flow.nodes, &(&1.type == "entry"))

    # 3. DFS traversal generating elements
    new_elements = traverse_flow(flow, entry_nodes, all_sheets)

    # 4. Diff: update existing mappeable elements, create new, delete orphaned
    diff_and_apply_elements(screenplay, new_elements, existing_map)

    # 5. Re-insert preserved elements (notes, sections, page_breaks) at their positions
    reinsert_preserved_elements(screenplay, preserved)
  end)
end

defp traverse_flow(flow, start_nodes, all_sheets) do
  # Build adjacency list from connections
  adjacency = build_adjacency(flow.connections)
  visited = MapSet.new()

  Enum.flat_map(start_nodes, fn entry ->
    {elements, _visited} = dfs(entry, adjacency, flow.nodes, all_sheets, visited, 0, nil)
    elements
  end)
end

defp dfs(node, adjacency, all_nodes, all_sheets, visited, depth, branch) do
  if MapSet.member?(visited, node.id) do
    {[], visited}
  else
    visited = MapSet.put(visited, node.id)
    elements = node_to_elements(node, all_sheets, depth, branch)
    next_nodes = get_next_nodes(node.id, adjacency, all_nodes)

    case node.type do
      "condition" ->
        # Branch: traverse true and false paths
        {true_elements, visited} = traverse_branch(next_nodes, "true", adjacency, all_nodes, all_sheets, visited, depth + 1)
        {false_elements, visited} = traverse_branch(next_nodes, "false", adjacency, all_nodes, all_sheets, visited, depth + 1)
        # Find merge point and continue
        {merge_elements, visited} = find_and_traverse_merge(next_nodes, adjacency, all_nodes, all_sheets, visited, depth)

        {elements ++ true_elements ++ false_elements ++ merge_elements, visited}

      _ ->
        # Sequential: traverse next node
        {next_elements, visited} =
          case next_nodes do
            [{_pin, next_node}] -> dfs(next_node, adjacency, all_nodes, all_sheets, visited, depth, branch)
            _ -> {[], visited}
          end
        {elements ++ next_elements, visited}
    end
  end
end
```

### 7.4 When to Sync from Flow

- **Manually**: User clicks "Sync from Flow" in toolbar
- **On open**: When opening a linked screenplay, offer to refresh from flow if flow has changed since last sync
- **Never automatic**: Flow edits don't auto-push to screenplay (would be disruptive while writing)

### 7.5 Conflict Resolution

When both screenplay and flow have been edited independently:

- Show a diff/merge UI (Phase 9+, future enhancement)
- For now: last-write-wins with user confirmation dialog
- Track `last_synced_at` timestamp on both screenplay and flow to detect divergence

---

## Phase 8: Dual Dialogue & Advanced Formatting

### 8.1 Dual Dialogue Block

Two characters speaking simultaneously, rendered side by side:

```elixir
def dual_dialogue_block(assigns) do
  ~H"""
  <div class="sp-dual-dialogue">
    <div class="sp-dual-column">
      <.character_input
        value={@element.data["left"]["character"]}
        sheet_id={@element.data["left"]["sheet_id"]}
        side="left"
        element_id={@element.id}
        all_sheets={@all_sheets}
      />
      <div :if={@element.data["left"]["parenthetical"]} class="sp-parenthetical">
        <%= @element.data["left"]["parenthetical"] %>
      </div>
      <.dialogue_input
        value={@element.data["left"]["dialogue"]}
        side="left"
        element_id={@element.id}
      />
    </div>

    <div class="sp-dual-column">
      <.character_input ... side="right" ... />
      <div :if={...} class="sp-parenthetical">...</div>
      <.dialogue_input ... side="right" ... />
    </div>
  </div>
  """
end
```

### 8.2 Character Extensions

Support standard extensions after character name:

```
JAIME (V.O.)      → Voice Over
JAIME (O.S.)      → Off Screen
JAIME (CONT'D)    → Continued (auto-detected when same speaker as previous)
```

The character element auto-appends `(CONT'D)` when the same speaker had the previous dialogue block.

### 8.3 Formatting Preview / Read Mode

A read-only mode that hides all interactive blocks and shows pure screenplay formatting:
- No condition/instruction/response blocks visible
- No note blocks visible
- Perfect for sharing with non-technical collaborators
- Toggle via button in toolbar

---

## Phase 9: Title Page & Export

### 9.1 Title Page Block

Special block rendered at the top of the screenplay:

```
                 LA TABERNA DEL CUERVO

                      Written by

                      Studio Dev


                                    Draft: February 2026
                                    Contact: studio@example.com
```

### 9.2 Fountain Export

Export screenplay as `.fountain` text file:

```elixir
defmodule Storyarn.Screenplays.Export.Fountain do
  def export(%Screenplay{} = screenplay) do
    elements = Screenplays.list_elements(screenplay.id)

    elements
    |> Enum.reject(&(&1.type in ["conditional", "instruction", "response", "note"]))
    |> Enum.map(&element_to_fountain/1)
    |> Enum.join("\n\n")
  end

  defp element_to_fountain(%{type: "title_page"} = el) do
    """
    Title: #{el.data["title"]}
    Credit: #{el.data["credit"]}
    Author: #{el.data["author"]}
    Draft date: #{el.data["draft_date"]}
    Contact: #{el.data["contact"]}
    """
  end

  defp element_to_fountain(%{type: "scene_heading"} = el) do
    String.upcase(el.content)
  end

  defp element_to_fountain(%{type: "action"} = el), do: el.content
  defp element_to_fountain(%{type: "character"} = el), do: String.upcase(el.content)
  defp element_to_fountain(%{type: "parenthetical"} = el), do: "(#{el.content})"
  defp element_to_fountain(%{type: "dialogue"} = el), do: el.content

  defp element_to_fountain(%{type: "transition"} = el) do
    "> #{String.upcase(el.content)}"
  end

  defp element_to_fountain(%{type: "page_break"}), do: "==="
  defp element_to_fountain(%{type: "section"} = el) do
    level = el.data["level"] || 1
    prefix = String.duplicate("#", level)
    "#{prefix} #{el.content}"
  end
  defp element_to_fountain(_), do: ""
end
```

### 9.3 PDF Export (Future)

Use a PDF rendering library to generate properly formatted screenplay PDFs. This is deferred to a later phase.

### 9.4 Import from Fountain

Parse `.fountain` files into screenplay elements. Use the Fountain spec to detect element types from text patterns.

---

## Key Design Decisions

### D1: Flat element list with depth/branch vs. nested tree

**Decision**: Flat list with `depth` and `branch` fields.

**Rationale**: Simpler database queries, easier reordering, matches how Rete.js/canvas nodes work (flat list with connections). The nesting is a rendering concern only.

### D2: `contenteditable` vs. TipTap for text blocks

**Decision**: `contenteditable` for standard blocks, TipTap only for `dialogue` and `action` blocks that need rich text.

**Rationale**: Scene headings, character names, transitions are plain text — no need for rich text. TipTap adds overhead. Use `contenteditable` directly for simple blocks and TipTap for blocks that need formatting (bold, italic, mentions).

### D3: Sync trigger

**Decision**: Manual sync with optional auto-sync toggle.

**Rationale**: Auto-sync on every edit would be expensive and disruptive. The user should control when the flow is updated from the screenplay and vice versa.

### D4: Conditional branching representation

**Decision**: Flat elements with `depth` + `branch` fields, rendered as nested blocks visually.

**Rationale**: Keeps the database simple while supporting visual nesting. Matches the flow graph model where condition nodes have labeled outputs (true/false).

### D5: Computed dialogue groups (no stored group_id)

**Decision**: Dialogue groups are computed from element adjacency at runtime, not stored in the database.

**Rationale**: A stored `group_id` becomes inconsistent when elements are reordered, inserted, or deleted. Computing groups from adjacency (character → parenthetical? → dialogue are consecutive) is O(n), trivial for typical element counts (<500), and impossible to become inconsistent. See Edge Case F.

### D6: Diff-based sync instead of clear + recreate

**Decision**: Both `sync_to_flow` and `sync_from_flow` use a diff approach that updates existing entities, creates new ones, and only deletes orphaned ones.

**Rationale**: Clear + recreate destroys manual work — canvas positions in flows, writer notes in screenplays. Diff-based sync preserves what it can while keeping content synchronized. See Edge Case C.

### D7: Flow node `source` field for sync ownership

**Decision**: Add `source` field ("manual" | "screenplay_sync") to `flow_nodes` to track which nodes were auto-generated by screenplay sync.

**Rationale**: Sync operations must know which nodes they "own" (safe to update/delete) vs which the user manually created in the canvas (must preserve). See Edge Case B.

### D8: Draft fields in schema from day one

**Decision**: Include `draft_of_id`, `draft_label`, and `draft_status` in the screenplay migration even though drafts are not implemented in the initial phases.

**Rationale**: Adding columns later requires a migration and risks breaking queries. Including them now (unused, nullable) costs nothing and ensures all queries include `WHERE draft_of_id IS NULL` from the start, preventing breakage when drafts are implemented. See FUTURE_FEATURES.md — Copy-Based Drafts.

---

## Testing Strategy

### Unit Tests

```
test/storyarn/screenplays/
├── screenplay_test.exs           # Schema validations
├── screenplay_element_test.exs   # Element schema + types
├── screenplay_crud_test.exs      # CRUD operations
├── element_crud_test.exs         # Element CRUD + reordering + splitting
├── element_grouping_test.exs     # Grouping logic
├── flow_sync_test.exs            # Bidirectional sync
└── tree_operations_test.exs      # Tree reordering
```

### LiveView Tests

```
test/storyarn_web/live/screenplay_live/
├── index_test.exs                # Sidebar, create, delete
└── show_test.exs                 # Editor, slash commands, block editing
```

### Key Test Scenarios

1. **Element CRUD**: Create, update, delete, reorder elements
2. **Split**: Split element at cursor, verify three new elements
3. **Computed grouping**: Consecutive character+dialogue → one group; reorder breaks group correctly
4. **Sync to flow (diff)**: Update existing nodes, create new, delete orphaned, preserve manual nodes
5. **Sync from flow (diff)**: Update existing elements, preserve notes/sections/page_breaks
6. **Conditional nesting**: Elements inside condition branches, depth 2+ nesting
7. **Response block**: Add/remove/edit choices; orphan response shows warning
8. **Slash commands**: Type detection, menu filtering, depth limit for /conditional
9. **Auto-detect**: Text pattern → element type
10. **Tree operations**: Sidebar hierarchy, drag-drop reorder
11. **Hub/Jump round-trip**: hub_marker → sync_to_flow → hub node → sync_from_flow → hub_marker
12. **Linked flow deleted**: Screenplay shows warning, unlink works
13. **Unique flow link**: Cannot link two screenplays to same flow
14. **Collaboration**: Element locking, presence, broadcast on element update

---

## Implementation Order

1. **Phase 1** — Database + schemas + context (backend only, no UI)
2. **Phase 2** — Sidebar + navigation + empty editor view
3. **Phase 3** — Core blocks (scene_heading, action, character, dialogue, parenthetical, transition)
4. **Phase 4** — Slash command system
5. **Phase 5** — Interactive blocks (conditional, instruction, response)
6. **Phase 6** — Screenplay → Flow sync
7. **Phase 7** — Flow → Screenplay sync
8. **Phase 8** — Dual dialogue + advanced formatting
9. **Phase 9** — Title page + Fountain export/import

Each phase is independently testable and deployable. Phases 1-5 deliver a fully functional standalone screenplay editor. Phases 6-7 add the flow integration. Phases 8-9 add polish.

**Prerequisite migration**: Before Phase 6, add `source` field to `flow_nodes` table (Edge Case B). This is a separate migration that can be done anytime before sync implementation.

---

## Dependencies

- **Existing**: Condition builder, instruction builder, variable system, TipTap editor, Collaboration module (presence + locks)
- **New migration needed**: `add_source_to_flow_nodes` — adds `source` field for sync ownership (Edge Case B)
- **No new deps needed**: All rendering is CSS + contenteditable + existing Phoenix LiveView
- **Lucide icons**: `scroll-text`, `clapperboard`, `align-left`, `columns-2`, `parentheses`, `scissors`
- **Future**: Draft system fields are in schema but not implemented — see FUTURE_FEATURES.md
