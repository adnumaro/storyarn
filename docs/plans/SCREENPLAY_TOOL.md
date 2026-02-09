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

| Phase   | Name                                                | Priority     | Status    |
|---------|-----------------------------------------------------|--------------|-----------|
| 1       | Database & Context                                  | Essential    | Done      |
| 2       | Sidebar & Navigation                                | Essential    | Done      |
| 3       | Screenplay Editor (Core Blocks)                     | Essential    | Done      |
| 4       | Slash Command System                                | Essential    | Done      |
| 5       | Interactive Blocks (Condition/Instruction/Response) | Essential    | Pending   |
| 6       | Flow Sync — Screenplay → Flow                       | Essential    | Pending   |
| 7       | Flow Sync — Flow → Screenplay                       | Essential    | Pending   |
| 8       | Dual Dialogue & Advanced Formatting                 | Important    | Pending   |
| 9       | Title Page & Export                                 | Nice to Have | Pending   |

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
