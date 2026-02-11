# Screenplay Tool Implementation Plan

> **Goal:** Add a new top-level tool "Screenplays" alongside Flows and Sheets that provides a professional screenplay editor with bidirectional sync to Flows.
>
> **Priority:** Major feature
>
> **Last Updated:** February 11, 2026

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

| Phase   | Name                                                | Priority     | Status     |
|---------|-----------------------------------------------------|--------------|------------|
| 1       | Database & Context                                  | Essential    | Done       |
| 2       | Sidebar & Navigation                                | Essential    | Done       |
| 3       | Screenplay Editor (Core Blocks)                     | Essential    | Done       |
| 4       | Slash Command System                                | Essential    | Done       |
| 5       | Interactive Blocks (Condition/Instruction/Response) | Essential    | Done       |
| 6       | Flow Sync — Screenplay → Flow                       | Essential    | Done       |
| 7       | Flow Sync — Flow → Screenplay                       | Essential    | Done       |
| 8       | Response Branching & Linked Pages                   | Essential    | Done       |
| 9       | Dual Dialogue & Advanced Formatting                 | Important    | Pending    |
| 10      | Title Page & Export                                 | Nice to Have | Pending    |

### Phase 1 — Summary (Done, 117 tests)

**Commit:** `93d3f33` — All 8 tasks complete, audited, 117 tests passing.

**Files created:**
- `priv/repo/migrations/20260209120000_create_screenplays.exs` — tables + indexes (Edge Case A unique partial index on linked_flow_id)
- `lib/storyarn/screenplays/screenplay.ex` — schema, 6 changesets (create/update/move/delete/restore/link_flow), `draft?/1`, `deleted?/1`
- `lib/storyarn/screenplays/screenplay_element.ex` — 16 element types, 4 changesets, type helpers (`types/0`, `standard_types/0`, `interactive_types/0`, `flow_marker_types/0`, `dialogue_group_types/0`, `non_mappeable_types/0`)
- `lib/storyarn/screenplays/screenplay_crud.ex` — list, list_tree, get, get!, create (auto-shortcut/position), update, delete (recursive soft-delete), restore, list_deleted
- `lib/storyarn/screenplays/element_crud.ex` — list, create, insert_at, update, delete (compact positions), reorder, split_element
- `lib/storyarn/screenplays/screenplay_queries.ex` — get_with_elements, count_elements, list_drafts
- `lib/storyarn/screenplays/tree_operations.ex` — reorder_screenplays, move_screenplay_to_position
- `lib/storyarn/screenplays/element_grouping.ex` — compute_dialogue_groups (O(n) single-pass), group_elements (with response attachment)
- `lib/storyarn/screenplays.ex` — context facade with defdelegate to all submodules
- `lib/storyarn/shortcuts.ex` — added `generate_screenplay_shortcut/3`
- `test/support/fixtures/screenplays_fixtures.ex` — screenplay_fixture, element_fixture
- 8 test files (117 tests total)

**Key patterns:** Follows Flows context exactly. Soft-delete + recursive children. Transaction error handling with explicit `case` + `Repo.rollback`. No `group_id` column (Edge Case F: computed from adjacency).

---

### Phase 2 — Summary (Done, 19 tests)

**Commit:** `73bf047` — All 6 tasks complete, audited, 19 tests.

**Tasks completed:** 2.1 `change_screenplay` changeset + delegate | 2.2 Routes + Index LiveView | 2.3 Layout + ProjectSidebar integration | 2.4 ScreenplayTree sidebar component | 2.5 Form modal create | 2.6 Index event handlers (CRUD + tree)

**Files created/modified:**
- `lib/storyarn_web/live/screenplay_live/index.ex` — list view with cards + modal
- `lib/storyarn_web/live/screenplay_live/show.ex` — show view (skeleton, enhanced in Phase 3)
- `lib/storyarn_web/live/screenplay_live/form.ex` — LiveComponent for create modal
- `lib/storyarn_web/components/sidebar/screenplay_tree.ex` — sidebar tree (SortableTree + TreeSearch)
- `lib/storyarn_web/components/sidebar/tree_helpers.ex` — shared tree helper functions
- `lib/storyarn_web/components/layouts.ex` — added `screenplays_tree` + `selected_screenplay_id` attrs
- `lib/storyarn_web/components/project_sidebar.ex` — 3-way tool switching (flows/screenplays/sheets)

**Key patterns:** Follows FlowLive.Index exactly. Authorization via `authorize(socket, :edit_content)`. Safe `parse_int/1` for user input. `active_tool` cond-based tree rendering.

---

### Phase 3 — Summary (Done, 28 show tests + 20 auto_detect tests)

**Commit:** `f3a9692` — All 6 tasks complete, audited, 48 tests.

**Tasks completed:** 3.1 Hook rename + Show LiveView + editor layout + CSS | 3.2 Element renderer + per-type blocks + CSS | 3.3 Contenteditable + ScreenplayElement hook + debounced save | 3.4 Enter key: create next element + server-side type inference | 3.5 Backspace (delete empty), Tab (cycle type), Arrow navigation | 3.6 Auto-detection + editor toolbar + screenplay name editing

**Files created:**
- `assets/css/screenplay.css` — industry-standard formatting (Courier 12pt, per-type margins/indentation, dark mode)
- `assets/js/hooks/screenplay_element.js` — per-element hook (debounced save, Enter/Backspace/Tab keydown, type change via DOM events)
- `assets/js/hooks/screenplay_editor_page.js` — page-level orchestrator (focus management, arrow navigation, server type-change propagation)
- `assets/js/hooks/dialogue_screenplay_editor.js` — renamed from `screenplay_editor.js` (frees the name)
- `lib/storyarn_web/components/screenplay/element_renderer.ex` — dispatch component (8 editable types, 7 stub types, page_break, fallback)
- `lib/storyarn/screenplays/auto_detect.ex` — pattern matching (scene_heading, character, transition, parenthetical)
- `test/storyarn/screenplays/auto_detect_test.exs` — 20 unit tests

**Files modified:**
- `lib/storyarn_web/live/screenplay_live/show.ex` — full editor: mount elements, 10 event handlers, `with_edit_permission` helper, `build_update_attrs` (auto-detect integration), `@next_type` server-side inference, `screenplays_path` helper, `do_create_screenplay` helper
- `lib/storyarn/screenplays.ex` — added `detect_type/1` delegate
- `assets/js/app.js` — registered 3 hooks (DialogueScreenplayEditor, ScreenplayElement, ScreenplayEditorPage)
- `assets/css/app.css` — imported screenplay.css
- `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` — updated phx-hook to DialogueScreenplayEditor

**Key patterns:** Server-side next-type inference via `@next_type` map (ignores client hint, fixes race condition with auto-detect). Cross-hook communication via custom DOM events (`typechanged`). `phx-update="ignore"` on editable elements with manual DOM class updates for type changes. `with_edit_permission/2` extracts authorization boilerplate. `screenplays_path/2` extracts URL construction. Safe `parse_int/1` for all client-sent IDs.

### Phase 4 — Summary (Done, 19 tests)

**Tasks completed:** 4.1 Slash command LiveView handlers + assigns (6 tests) | 4.2 Slash Command Menu HEEx component + CSS (5 tests) | 4.3 SlashCommand JS hook — keyboard, search, mouse (JS-only) | 4.4 Slash key detection in ScreenplayElement hook (4 tests) | 4.5 Mid-text slash: split element + open menu (4 tests)

**Files created:**
- `lib/storyarn_web/components/screenplay/slash_command_menu.ex` — floating command palette (12 commands in 3 groups: Screenplay, Interactive, Utility), `slash_group` and `slash_item` sub-components, Lucide icons
- `assets/js/hooks/slash_command.js` — menu hook: positioning via `getBoundingClientRect`, keyboard navigation (Arrow/Enter/Escape), search filtering, mouse support, cleanup in `destroyed()`

**Files modified:**
- `lib/storyarn_web/live/screenplay_live/show.ex` — 4 event handlers: `open_slash_menu`, `select_slash_command`, `split_and_open_slash_menu`, `close_slash_menu`; `@slash_menu_element_id` assign; type validation via `ScreenplayElement.types()`; `parse_int` on `cursor_position` for safety
- `assets/js/hooks/screenplay_element.js` — `/` key detection in `handleKeyDown`: empty element → `open_slash_menu`, non-empty at valid position (start, after space/newline) → `split_and_open_slash_menu`; `getCursorOffset()` helper using Range API; `flushDebounce()` before split
- `assets/css/screenplay.css` — `.slash-menu` styles: fixed positioning, dark mode, search input, group labels, item hover/highlight states, hidden states for filtered items/groups

**Key patterns:** Server controls menu visibility via `@slash_menu_element_id` assign. JS hook handles positioning and keyboard interaction. `phx-click-away` closes menu on outside click. Mid-text `/` only triggers at valid positions (preserves "INT./EXT." typing). `cursor_position` parsed to integer server-side for safety.

### Phase 5 — Summary (Done, 20 tests)

**Tasks completed:** 5.1 Load project variables + wire to element renderer | 5.2 Conditional block — inline condition builder (5 tests) | 5.3 Instruction block — inline instruction builder (5 tests) | 5.4 Response block — basic choices management (5 tests) | 5.5 Response per-choice condition and instruction (5 tests)

**Files modified:**
- `lib/storyarn_web/components/condition_builder.ex` — added `event_name` attr, `data-event-name` to template
- `lib/storyarn_web/components/instruction_builder.ex` — added `context` and `event_name` attrs, `data-context` and `data-event-name` to template
- `assets/js/hooks/condition_builder.js` — custom event name support in `pushCondition()`: if `eventName` is set, push custom event with `{condition, ...context}` and return early
- `assets/js/hooks/instruction_builder.js` — custom event name and context support in `pushAssignments()`: same pattern as condition_builder
- `lib/storyarn_web/components/screenplay/element_renderer.ex` — 3 new `render_block` clauses for conditional (inline condition builder), instruction (inline instruction builder), response (server-rendered choices with per-choice condition/instruction toggles); removed conditional/instruction/response from `@stub_types`; imports ConditionBuilder, InstructionBuilder, CoreComponents
- `lib/storyarn_web/live/screenplay_live/show.ex` — loads `project_variables` in mount; 9 new event handlers: `update_screenplay_condition`, `update_screenplay_instruction`, `add_response_choice`, `remove_response_choice`, `update_response_choice_text`, `toggle_choice_condition`, `toggle_choice_instruction`, `update_response_choice_condition`, `update_response_choice_instruction`; `update_choice_field/4` private helper for per-choice updates; aliases `Condition`, `Instruction`, `Sheets`
- `assets/css/screenplay.css` — interactive block styles (`.sp-interactive-block`, `.sp-interactive-header`, `.sp-interactive-label`, per-type accent colors), choice row styles (`.sp-choice-row`, `.sp-choice-input`, `.sp-choice-toggle`, `.sp-choice-extras`, `.sp-add-choice`), dark mode for choice inputs

**Key patterns:** `event_name` attr on builders enables reuse in screenplay editor without modifying existing flow editor paths. Response block uses standard `<input>` + `phx-blur`/`phx-click` (no custom JS hook — KISS). Per-choice condition/instruction use same builder components with toggle visibility. All handlers go through `with_edit_permission`. Conditions sanitized via `Condition.sanitize/1`, assignments via `Instruction.sanitize/1`. No branching/nesting (depth/branch) — deferred to a separate phase.

### Phase 6 — Summary (Done, 41 tests)

**Tasks completed:** 6.1 Migration — add `source` field to `flow_nodes` (3 tests) | 6.2 NodeMapping — pure element-to-node conversion (13 tests) | 6.3 FlowSync — ensure_flow, link, unlink (6 tests) | 6.4 sync_to_flow — diff-based sync engine (11 tests) | 6.5 Auto-layout algorithm (3 tests) | 6.6 UI toolbar sync controls + LiveView handlers (5 tests)

**Files created:**
- `priv/repo/migrations/20260209180000_add_source_to_flow_nodes.exs` — adds `source` string field (default "manual", not null) + index
- `lib/storyarn/screenplays/node_mapping.ex` — pure-function module converting element groups to flow node attr maps; handles all 14 element types (scene_heading→entry/scene, dialogue group, action, conditional, instruction, response orphan, transition, hub_marker, jump_marker, dual_dialogue skip, non-mappeable skip); INT./EXT. parsing; response choice serialization with condition/instruction
- `lib/storyarn/screenplays/flow_sync.ex` — sync engine: `ensure_flow/1` (create or return flow), `link_to_flow/2` (with project validation), `unlink_flow/1` (transaction: clear element links + screenplay link), `sync_to_flow/1` (diff-based: group elements → map to node attrs → create/update/delete synced nodes → create connections → auto-layout new nodes → link elements)
- `test/storyarn/flows/flow_node_test.exs` — 3 tests for source field validation
- `test/storyarn/screenplays/node_mapping_test.exs` — 13 tests for all mapping functions
- `test/storyarn/screenplays/flow_sync_test.exs` — 20 tests (lifecycle + sync + auto-layout)

**Files modified:**
- `lib/storyarn/flows/flow_node.ex` — added `source` field, `@valid_sources`, validation in create_changeset
- `lib/storyarn/flows.ex` — added `get_flow_including_deleted/2` delegate for soft-delete detection
- `lib/storyarn/screenplays.ex` — added delegates: `ensure_flow/1`, `link_to_flow/2`, `unlink_flow/1`, `sync_to_flow/1`
- `lib/storyarn_web/live/screenplay_live/show.ex` — link status detection in mount (`detect_link_status/1` → `:unlinked | :linked | :flow_deleted | :flow_missing`); toolbar sync controls (conditional rendering per status); 4 event handlers: `create_flow_from_screenplay`, `sync_to_flow`, `unlink_flow`, `navigate_to_flow`
- `assets/css/screenplay.css` — sync control styles: `.screenplay-toolbar-separator`, `.sp-sync-btn`, `.sp-sync-btn-subtle`, `.sp-sync-badge`, `.sp-sync-linked`, `.sp-sync-warning`
- `test/storyarn_web/live/screenplay_live/show_test.exs` — 5 new tests for toolbar sync controls

**Key patterns:** Diff-based sync (Edge Case C) — never clear + recreate, preserves manual nodes and XY positions. `source` field on `flow_nodes` ("manual" | "screenplay_sync") distinguishes sync ownership (Edge Case B). NodeMapping is pure (no DB), FlowSync handles all side effects in transactions. Auto-layout: x=400, y_start=100, y_spacing=150 — only new nodes get positioned, existing keep their positions. Condition nodes connect both `true` and `false` to next node (flat, no branching yet). Orphan response creates empty dialogue wrapper (Edge Case E). Hub/jump markers round-trip safely (Edge Case D).

### Phase 7 — Summary (Done, 47 tests)

**Tasks completed:** 7.1 ReverseNodeMapping — pure node→element(s) conversion (23 tests) | 7.2 FlowTraversal — linearize flow graph via DFS (10 tests) | 7.3 FlowSync.sync_from_flow — diff engine (11 tests) | 7.4 UI — toolbar "Sync from Flow" button + handler (3 tests)

**Files created:**
- `lib/storyarn/screenplays/reverse_node_mapping.ex` — pure-function module converting flow nodes to element attr maps; handles all node types (entry→scene_heading, scene→scene_heading, dialogue→character+parenthetical?+dialogue+response?, action-style dialogue→action, condition→conditional, instruction→instruction, exit→transition, hub→hub_marker, jump→jump_marker, subflow→skip); response choice deserialization (condition via `Condition.parse/1`, instruction via `Jason.decode/1`)
- `lib/storyarn/screenplays/flow_traversal.ex` — pure-function module for DFS graph linearization; builds adjacency list from connections, traverses from entry nodes following primary pin ("output" for standard, "true" for conditions), cycle detection via visited set, multiple entry support with shared visited set
- `test/storyarn/screenplays/reverse_node_mapping_test.exs` — 23 tests (all node types, dialogue variants, deserialization, multi-node expansion)
- `test/storyarn/screenplays/flow_traversal_test.exs` — 10 tests (linear chain, condition branching, terminals, cycles, hub, multiple entries, disconnected nodes, complex paths)

**Files modified:**
- `lib/storyarn/screenplays/flow_sync.ex` — added `sync_from_flow/1` with full pipeline: validate link → load nodes + connections → FlowTraversal.linearize → ReverseNodeMapping.nodes_to_element_attrs → diff against existing elements (group by source_node_id/linked_node_id, match by type) → create/update/delete → preserve non-mappeable with anchor strategy → recompact positions
- `lib/storyarn/screenplays.ex` — added `sync_from_flow/1` delegate
- `lib/storyarn_web/live/screenplay_live/show.ex` — renamed "Sync" button to "To Flow" (upload icon), added "From Flow" button (download icon), added `sync_from_flow` event handler with error handling for not-linked and no-entry-node
- `test/storyarn/screenplays/flow_sync_test.exs` — 11 new tests (not-linked error, no-entry-node error, create elements from flow, dialogue expansion, action-style, re-sync update, orphan deletion, non-mappeable preservation, anchor positioning, linked_node_id, subflow skip)
- `test/storyarn_web/live/screenplay_live/show_test.exs` — 3 new tests (sync_from_flow success, not-linked error, viewer permission), updated existing test for renamed button text

**Key patterns:** ReverseNodeMapping and FlowTraversal are pure modules (no DB) for testability. Anchor-based non-mappeable preservation: each note/section/page_break records the `linked_node_id` of the next mappeable element as its anchor; after sync, non-mappeable elements are re-inserted before their anchor. Multi-element diff: dialogue nodes produce 2-4 elements, diff groups by `source_node_id`/`linked_node_id` and matches within each group by element type. Condition nodes follow primary path only ("true" pin) — symmetric with Phase 6's flat approach. All nodes synced (both `source: "manual"` and `source: "screenplay_sync"`).

### Phase 8 — Summary (Done, 156 tests total across all Phase 8 files)

**Tasks completed:** 8.1 LinkedPageCrud — create/link/unlink choice pages (10 tests) | 8.2 PageTreeBuilder — recursive page tree → flat node attrs + connections (10 tests) | 8.3 FlowTraversal update — `linearize_tree/2` with response branches (4 tests) | 8.4 FlowSync update — multi-page sync_to_flow + sync_from_flow with branching (22 tests) | 8.5 FlowLayout — tree-aware auto-layout with horizontal branching (4 tests) | 8.6 UI — linked page controls in response block + sidebar tree navigation (5 tests) | 8.audit — audit fixes (6 tasks, see below)

**Files created:**
- `lib/storyarn/screenplays/linked_page_crud.ex` — CRUD for linked pages: `create_linked_page/3` (creates child screenplay + sets `linked_screenplay_id` on choice), `link_choice/4`, `unlink_choice/2`, `linked_screenplay_ids/1`, `list_child_screenplays/1`, `find_choice/2` (public), `update_choice/3` (public)
- `lib/storyarn/screenplays/page_tree_builder.ex` — pure-function module: `build/1` (recursive page data → tree with `node_attrs_list` + `branches`), `flatten/1` (tree → flat `all_node_attrs` + `connections` + `screenplay_ids` for sync engine)
- `lib/storyarn/screenplays/flow_layout.ex` — pure-function module: `compute_positions/2` (tree-aware layout with horizontal branching at response nodes, `@x_gap 350`, `@y_spacing 150`), bounds-safe with nil guard on `Enum.at`
- `test/storyarn/screenplays/linked_page_crud_test.exs` — 10 tests
- `test/storyarn/screenplays/page_tree_builder_test.exs` — 10 tests
- `test/storyarn/screenplays/flow_layout_test.exs` — 4 tests

**Files modified:**
- `lib/storyarn/screenplays/flow_traversal.ex` — added `linearize_tree/2` (DFS with branch collection at dialogue response pins), made `response_ids/1` public; removed unused `linearize/2` and `traverse/4` (audit A.1, A.3)
- `lib/storyarn/screenplays/flow_sync.ex` — `sync_to_flow` updated to load full page tree via `load_descendant_data` + `PageTreeBuilder`, multi-page node creation + branching connections; `sync_from_flow` updated with `sync_page_from_tree!` recursive sync + `sync_branch_from_tree!` (creates child pages from flow branches); `cleanup_orphaned_links!` unlinks choices whose branches no longer exist in flow; added `@max_tree_depth 20` recursion guard (audit A.4); refactored `create_branch_child!` to use pattern match instead of `Repo.rollback` (audit A.5); consolidated choice helpers via `LinkedPageCrud` (audit A.2)
- `lib/storyarn/screenplays.ex` — added delegates: `create_linked_page`, `link_choice`, `unlink_choice`, `linked_screenplay_ids`, `list_child_screenplays`, `find_choice`, `update_choice`, `screenplay_exists?`
- `lib/storyarn/screenplays/screenplay_crud.ex` — added `screenplay_exists?/2` for navigation validation (audit A.6)
- `lib/storyarn_web/live/screenplay_live/show.ex` — 4 new linked page event handlers (`create_linked_page`, `navigate_to_linked_page`, `unlink_choice_screenplay`, `generate_all_linked_pages`); `valid_navigation_target?/2` check for defense-in-depth (audit A.6); uses `LinkedPageCrud.find_choice/2` instead of local duplicate (audit A.2)
- `lib/storyarn_web/components/screenplay/element_renderer.ex` — response block shows linked page indicators (link icon + page name or create affordance)
- `assets/css/screenplay.css` — linked page styles (`.sp-choice-link`, `.sp-choice-create-link`, `.sp-generate-all`)
- `test/storyarn/screenplays/flow_traversal_test.exs` — removed 10 `linearize/2` tests (covered by `linearize_tree/2`)
- `test/storyarn/screenplays/flow_sync_test.exs` — 22 new multi-page tests (branch connections, child page creation, nested branches, orphan cleanup, re-sync, depth safety)
- `test/storyarn_web/live/screenplay_live/show_test.exs` — 5 new linked page tests

**Audit fixes (Phase 8 audit):**
- A.1: Removed dead code `linearize/2` + `traverse/4` from FlowTraversal (-35 LOC)
- A.2: Consolidated duplicated choice helpers → single source in `LinkedPageCrud` (3 copies → 1)
- A.3: Consolidated `response_ids` → single public function in `FlowTraversal` (2 copies → 1)
- A.4: Added `@max_tree_depth 20` depth guards to `load_descendant_data`, `sync_page_from_tree!`, `sync_branch_from_tree!`
- A.5: Bounds-safe `FlowLayout.layout_node/7` (nil guard on Enum.at), `create_branch_child!` uses pattern match instead of `Repo.rollback`
- A.6: `screenplay_exists?/2` + `valid_navigation_target?/2` defense-in-depth on navigate

**Key patterns:** Response choices store `linked_screenplay_id` in JSON data (no migration). `PageTreeBuilder` is pure (no DB) — converts recursive page data into flat node attrs + connection specs. Multi-page sync: all pages in a tree sync to the root's single flow. `linearize_tree/2` produces a recursive tree result with branches; `sync_from_flow` creates child pages from flow branches and recursively syncs each. Layout algorithm branches horizontally at response nodes with `@x_gap 350px` between columns.

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

**When:** ~~Implement in Phase 3 alongside the core editor.~~ **Deferred to Phase 3.5** — Phase 3 editor includes `data-element-id` attributes on all elements, making locking straightforward to add. The editor UI is collaboration-aware by design (element-level focus events), so retrofitting is minimal.

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

### K. Response branching & linked pages

**Problem:** Game narratives are non-linear. Dialogue response choices need to branch into different story paths, but the original plan treats responses as inert data with no destination — the sync produces a flat linear chain regardless of how many responses a dialogue has.

**Solution:** Response choices gain a `linked_screenplay_id` field (stored in the JSON `data`, no migration needed). Each choice can link to a child screenplay page in the tree. The sync engine traverses the full tree recursively: when it encounters a response with a linked page, it creates a connection from the response output pin to the first node of that child page's content. The auto-layout algorithm branches horizontally at response nodes.

**UX:** The writer creates linked pages via double-click on a response choice, right-click context menu, or a bulk "Generate all pages" button. Child pages appear in the sidebar tree under the parent. Visual indicators show which choices are linked and which child pages are empty.

**Phase:** 8 — implemented after Phase 6/7 (linear sync), updates the sync engine and layout algorithm.

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

## Phase 1: Database & Context (Done)

Covered in [Phase 1 Summary](#phase-1--summary-done-117-tests) above. Reference code removed — see committed files.

## Phase 2: Sidebar & Navigation (Done)

Covered in [Phase 2 Summary](#phase-2--summary-done-19-tests) above. Reference code removed — see committed files.

---

## Phase 3: Screenplay Editor (Core Blocks)

> **Note:** Collaboration (Edge Case H) has been **deferred to Phase 3.5**. The editor
> includes `data-element-id` attributes on all elements, making locking easy to add later.

This phase transforms `ScreenplayLive.Show` from a skeleton into a functional block-based screenplay editor with industry-standard formatting, keyboard-driven writing flow, and auto-detection.

**Key deliverables:**
- Screenplay page container with Courier 12pt monospace layout (8.5" × 11" page)
- Element renderer dispatching to per-type block components with correct CSS (margins, indentation, text-transform)
- `contenteditable` blocks with `ScreenplayElement` JS hook (debounced save, 500ms)
- Keyboard flow: Enter (create next + type inference), Backspace (delete empty), Tab (cycle type), Arrow keys (navigate between elements)
- `ScreenplayEditor` page-level JS hook (focus management, arrow navigation)
- Auto-detect element type from text patterns (INT./EXT. → scene_heading, ALL CAPS → character, etc.)
- Editor toolbar with editable screenplay name
- Interactive blocks (`conditional`, `instruction`, `response`) render as stubs — full implementation in Phase 5

**Prerequisite:** Rename existing `ScreenplayEditor` hook (dialogue fullscreen editor) → `DialogueScreenplayEditor` to free the name.

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

## Phase 5: Interactive Blocks (Done)

Covered in [Phase 5 Summary](#phase-5--summary-done-20-tests) above. Reference code removed — see committed files.

---

## Phase 6: Flow Sync — Screenplay → Flow (Done)

Covered in [Phase 6 Summary](#phase-6--summary-done-41-tests) above. Reference code removed — see committed files.

---

## Phase 7: Flow Sync — Flow → Screenplay (Done)

Covered in [Phase 7 Summary](#phase-7--summary-done-47-tests) above. Reference code removed — see committed files.

---

## Phase 8: Response Branching & Linked Pages

> **Prerequisite:** Phase 6 (Screenplay → Flow sync) and Phase 7 (Flow → Screenplay sync)
>
> **Why this phase exists:** The screenplay tool serves narrative game design — not film. Game narratives are non-linear: dialogue responses branch into different story paths. Without this phase, response choices are inert data with no destination. This phase makes the screenplay tree the source of truth for the game's narrative graph.

### Overview

Response choices link to **child screenplay pages**, turning the sidebar tree into the narrative branching structure. Each response creates a separate story path that the writer authors on its own page. The sync engine (Phase 6) is updated to traverse the full page tree and generate branching flow connections, and the auto-layout algorithm is updated to position branches horizontally.

### Core Concepts

1. **Linked Pages** — Each response choice gains a `linked_screenplay_id` field pointing to a child screenplay page. The choice text becomes the branch label; the child page contains the full scene for that branch.

2. **Screenplay Tree = Narrative Graph** — The existing `parent_id` tree structure already supports parent-child relationships. This phase gives that tree semantic meaning: a child page IS a narrative branch reached via a response choice in the parent.

3. **Multi-page Sync** — All pages in a screenplay tree sync to the **same flow** (the root's `linked_flow_id`). Each page contributes nodes to the shared flow. Response pins connect to the first node of each child page's content.

4. **Branching Layout** — The auto-layout algorithm (Phase 6, Task 6.5) is replaced with a tree-aware layout that branches horizontally at response nodes and stacks each branch's nodes vertically.

### Data Model Changes

**Response choice — add `linked_screenplay_id`:**
```elixir
# In element.data["choices"]
%{
  "id" => "c1",
  "text" => "I need a room",
  "condition" => nil,
  "instruction" => nil,
  "linked_screenplay_id" => 42  # FK → screenplays (child page)
}
```

No schema migration needed — `linked_screenplay_id` lives inside the JSON `data` field. Validation ensures the referenced screenplay exists and is a child of the current page.

### UX: Creating Linked Pages from Responses

When a writer adds response choices via `/responses`, each choice is initially unlinked (no destination page). The writer creates linked pages through:

1. **Double-click** on a response choice → creates a new child screenplay page named after the choice text, auto-links it, and navigates to it
2. **Right-click context menu** on a choice → "Create page for this response"
3. **"Generate all pages" button** in the response block header → creates child pages for all unlinked choices in bulk
4. **Link to existing page** — dropdown/search to link a choice to an already-existing screenplay page in the tree

After linking, the choice row shows the page name as a clickable link for quick navigation.

### Visual Indicators

| State                                  | Indicator                                                          |
|----------------------------------------|--------------------------------------------------------------------|
| Response choice with linked page       | Filled link icon + page name (clickable → navigates to child page) |
| Response choice without linked page    | Empty link icon + "Create page" affordance                         |
| Empty child page in sidebar tree       | Subtle draft/empty icon (e.g., faded or dotted)                    |
| Child page with content                | Normal page icon in tree                                           |
| Response block with all choices linked | Green checkmark on block header                                    |
| Response block with unlinked choices   | Warning indicator on block header                                  |

### Sync Engine Updates (extends Phase 6)

Phase 6's `sync_to_flow/1` processes a single screenplay page linearly. This phase updates it to:

1. **Recursive tree traversal** — `sync_to_flow` starts at the root page and, when it encounters a response with `linked_screenplay_id`, recursively processes the child page's elements before continuing.

2. **Response branching connections** — Instead of `dialogue.output → next_node`, each linked response choice creates a connection from its output pin (`response_0`, `response_1`, ...) to the **first node** of the child page's content.

3. **Multi-page node generation** — Each child page's elements generate nodes in the shared flow. The first scene_heading of a child page maps to a `scene` node (not `entry` — only the root page's first scene_heading is `entry`).

4. **Orphan cleanup scope** — Expanded to include nodes from deleted child pages. If a child page is removed from the tree or a choice is unlinked, the corresponding synced nodes are deleted.

5. **Element linking across pages** — Elements from all pages in the tree receive `linked_node_id` pointing to their corresponding node in the shared flow.

**Connection rules update:**

| Source node                                 | Condition   | Connection                                                         |
|---------------------------------------------|-------------|--------------------------------------------------------------------|
| Dialogue without responses                  | —           | `output` → next sequential node                                    |
| Dialogue with linked responses              | Each choice | `response_N` → first node of child page N                          |
| Dialogue with unlinked responses            | Fallback    | `output` → next sequential node                                    |
| Dialogue with mixed (some linked, some not) | Per choice  | Linked: `response_N` → child; Unlinked: no connection for that pin |
| Condition node                              | —           | `true` + `false` → next node (unchanged)                           |

### Layout Algorithm Update (replaces Phase 6 Task 6.5)

The simple vertical stack is replaced with a tree-aware layout:

1. **Sequential segments** — nodes without branches stack vertically (same as Phase 6)
2. **Response branches** — when a dialogue node has N linked responses, the layout creates N horizontal columns below it
3. **Column layout** — each column contains the child page's nodes stacked vertically
4. **Horizontal spacing** — columns are evenly spaced with a configurable gap (e.g., 300px between column centers)
5. **Recursive branching** — child pages that themselves have responses branch further (the algorithm is recursive)
6. **Column width calculation** — each column's width is determined by the widest subtree it contains (to prevent overlap)
7. **Convergence** — if branches reconverge via hub/jump markers, the layout returns to center

### Scope & Constraints

- **No depth limit** — a response in a child page can link to a grandchild page, and so on. The tree/flow can be arbitrarily deep.
- **Cross-page hub/jump** — hub_marker and jump_marker elements can reference nodes across pages (e.g., a jump in page B targeting a hub in page A).
- **Root-only flow link** — only the root screenplay has `linked_flow_id`. Child pages don't have their own flows — they contribute to the parent's flow.
- **Phase 7 (Flow → Screenplay) impact** — `sync_from_flow` must also be updated to handle the tree structure: when traversing response branches in the flow, it maps them to child pages (or creates them if they don't exist).
- **Collaboration** — real-time collaboration (Edge Case H) extends naturally to child pages since they're independent screenplay records.

### What This Phase Does NOT Cover

- **Condition branching** (depth/branch) — conditionals with nested true/false element branches remain deferred. Condition nodes sync their data but connect linearly.
- **Dual dialogue** — side-by-side dialogue remains deferred to Phase 9.
- **Visual flow preview** — an inline minimap showing the narrative graph within the screenplay editor is a future enhancement.

---

## Phase 9: Dual Dialogue & Advanced Formatting

### 9.1 Dual Dialogue Block

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

### 9.2 Character Extensions

Support standard extensions after character name:

```
JAIME (V.O.)      → Voice Over
JAIME (O.S.)      → Off Screen
JAIME (CONT'D)    → Continued (auto-detected when same speaker as previous)
```

The character element auto-appends `(CONT'D)` when the same speaker had the previous dialogue block.

### 9.3 Formatting Preview / Read Mode

A read-only mode that hides all interactive blocks and shows pure screenplay formatting:
- No condition/instruction/response blocks visible
- No note blocks visible
- Perfect for sharing with non-technical collaborators
- Toggle via button in toolbar

---

## Phase 10: Title Page & Export

### 10.1 Title Page Block

Special block rendered at the top of the screenplay:

```
                 LA TABERNA DEL CUERVO

                      Written by

                      Studio Dev


                                    Draft: February 2026
                                    Contact: studio@example.com
```

### 10.2 Fountain Export

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

### 10.3 PDF Export (Future)

Use a PDF rendering library to generate properly formatted screenplay PDFs. This is deferred to a later phase.

### 10.4 Import from Fountain

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
6. **Phase 6** — Screenplay → Flow sync (linear)
7. **Phase 7** — Flow → Screenplay sync (linear)
8. **Phase 8** — Response branching & linked pages (non-linear narratives, updates sync + layout)
9. **Phase 9** — Dual dialogue + advanced formatting
10. **Phase 10** — Title page + Fountain export/import

Each phase is independently testable and deployable. Phases 1-5 deliver a fully functional standalone screenplay editor. Phases 6-7 add linear flow integration. Phase 8 makes the system work for interactive/branching narratives. Phases 9-10 add polish.

**Prerequisite migration**: ~~Before Phase 6, add `source` field to `flow_nodes` table (Edge Case B).~~ Done in Phase 6 Task 6.1.

---

## Dependencies

- **Existing**: Condition builder, instruction builder, variable system, TipTap editor, Collaboration module (presence + locks)
- **Migration done**: `add_source_to_flow_nodes` — `source` field for sync ownership (Edge Case B, Phase 6 Task 6.1)
- **No new deps needed**: All rendering is CSS + contenteditable + existing Phoenix LiveView
- **Lucide icons**: `scroll-text`, `clapperboard`, `align-left`, `columns-2`, `parentheses`, `scissors`
- **Future**: Draft system fields are in schema but not implemented — see FUTURE_FEATURES.md
