# Screenplay Tool Implementation Plan

> **Goal:** Add a new top-level tool "Screenplays" alongside Flows and Sheets that provides a professional screenplay editor with bidirectional sync to Flows.
>
> **Priority:** Major feature
>
> **Last Updated:** February 13, 2026

## Overview

Screenplay is a **unified TipTap editor** where the entire document is a single ProseMirror instance. Each element type is a custom TipTap `Node.create()` extension — text blocks have `content: "inline*"`, interactive/utility blocks are atom NodeViews that communicate with LiveView via event bubbling.

**Key Principles:**
- Screenplay is an **independent entity** — can exist without a linked flow
- When linked to a flow, edits in either sync bidirectionally (manual trigger)
- Uses industry-standard screenplay formatting (Fountain-compatible, Courier 12pt)
- Slash commands (`/conditional`, `/instruction`, etc.) via TipTap Suggestion API (client-side, no server round-trip)
- Each block maps to a flow node; consecutive character+dialogue blocks group into one node

**Industry Format Reference:** Courier 12pt monospaced, specific margins per element type. See [Fountain syntax spec](https://fountain.io/syntax/).

---

## Implementation Status

| Phase     | Name                                                | Status |
|-----------|-----------------------------------------------------|--------|
| 1         | Database & Context                                  | Done   |
| 2         | Sidebar & Navigation                                | Done   |
| 3         | Screenplay Editor (Core Blocks)                     | Done   |
| 4         | Slash Command System                                | Done   |
| 5         | Interactive Blocks (Condition/Instruction/Response) | Done   |
| 6         | Flow Sync — Screenplay → Flow                       | Done   |
| 7         | Flow Sync — Flow → Screenplay                       | Done   |
| 8         | Response Branching & Linked Pages                   | Done   |
| 9         | Dual Dialogue & Advanced Formatting                 | Done   |
| TipTap    | Unified TipTap Editor Migration                     | Done   |
| 10        | Title Page & Export                                 | Done   |

**Total tests:** 1404 passing (75 show_test, 18 test files under `test/storyarn/screenplays/`)

---

## Phase Summaries (Done)

### Phase 1 — Database & Context (117 tests)

**Commit:** `93d3f33`

Schemas (`screenplay.ex`, `screenplay_element.ex`), CRUD modules (`screenplay_crud.ex`, `element_crud.ex`), queries, tree operations, element grouping. Context facade with `defdelegate`. 16 element types, soft-delete + recursive children, computed dialogue groups (no `group_id` — Edge Case F). Unique partial index on `linked_flow_id` (Edge Case A).

### Phase 2 — Sidebar & Navigation (19 tests)

**Commit:** `73bf047`

Routes, `Index` LiveView, `Form` LiveComponent, `ScreenplayTree` sidebar component, `ProjectSidebar` 3-way tool switching. Follows `FlowLive.Index` patterns.

### Phase 3 — Core Block Editor (48 tests)

**Commit:** `f3a9692`

First editor implementation with per-element contenteditable hooks, server-side type inference, auto-detection (`auto_detect.ex`), CSS (`screenplay.css`), keyboard flow (Enter/Backspace/Tab/Arrow).

> **Note:** The UI layer (per-element hooks, `element_renderer.ex`) was later replaced by the unified TipTap migration. The backend (auto_detect, CSS, show.ex handlers) persists.

### Phase 4 — Slash Command System (19 tests)

Original server-controlled slash menu with Phoenix component + JS hook. Later replaced by client-side TipTap Suggestion API in the TipTap migration.

### Phase 5 — Interactive Blocks (20 tests)

**Commit:** `ba6cb32`

Inline condition builder, instruction builder, response choices with per-choice condition/instruction toggles. Added `event_name` attr to builders for reuse in screenplay context. All handlers through `with_edit_permission`. Original Phoenix component rendering later replaced by TipTap atom NodeViews.

### Phase 6 — Flow Sync: Screenplay → Flow (41 tests)

**Commit:** `3981abd`

Migration adds `source` field to `flow_nodes` ("manual" | "screenplay_sync"). `NodeMapping` (pure) converts element groups to node attrs. `FlowSync` engine: diff-based create/update/delete (Edge Case C), preserves manual nodes (Edge Case B). Auto-layout for new nodes. Toolbar sync controls.

### Phase 7 — Flow Sync: Flow → Screenplay (47 tests)

**Commit:** `a5169b4`

`ReverseNodeMapping` (pure) converts flow nodes to element attrs. `FlowTraversal` (pure) linearizes flow graph via DFS. `sync_from_flow` diff engine with anchor-based non-mappeable preservation. Hub/jump markers round-trip safely (Edge Case D).

### Phase 8 — Response Branching & Linked Pages (156 tests)

**Commit:** `244c021`

`LinkedPageCrud` for create/link/unlink choice pages. `PageTreeBuilder` (pure) converts recursive page data to flat node attrs + connections. `FlowLayout` (pure) tree-aware auto-layout with horizontal branching. Multi-page sync to single flow. `@max_tree_depth 20` recursion guard. Sidebar tree navigation.

### Phase 9 — Dual Dialogue & Advanced Formatting (1315 total tests)

**Commit:** `9981197`

`CharacterExtension` (pure) parses V.O., O.S., CONT'D. Dual dialogue element with `left`/`right` sub-maps. Forward + reverse node mapping for dual dialogue. Read mode toggle (filters interactive types via CSS). `SCREENPLAY_FORMAT_CONVENTIONS.md` reference document.

### Unified TipTap Migration (3 phases)

**Commits:** `fd9a480` (Phase 1), `0a839cf` (Phase 2), `e8d90ad` (Phase 3)

Replaced the hybrid editor (per-element TipTap + contenteditable + static HTML + Phoenix components) with a **single TipTap `Editor` instance**. All 16 element types are custom TipTap nodes. Text blocks use `content: "inline*"`. Interactive blocks (conditional, instruction, response, dual_dialogue) and markers (hub, jump, title_page, page_break) are atom NodeViews communicating with LiveView via CustomEvent bubbling.

**What was replaced:**
- Per-element hooks (`screenplay_element.js`, `screenplay_editor_page.js`) → single `screenplay_editor.js` hook
- Server-rendered `element_renderer.ex` → JS NodeViews in `assets/js/screenplay/nodes/`
- Server-controlled slash menu (`slash_command_menu.ex`, `slash_command.js`) → client-side TipTap Suggestion API
- Server-side CONT'D computation → client-side ProseMirror decoration plugin (`contd_plugin.js`)
- Transition left-align check → client-side decoration plugin (`transition_align_plugin.js`)
- Per-element events (`create_next_element`, `delete_element`, `change_element_type`) → single `sync_editor_content` event

**What was added:**
- `TiptapSerialization` (Elixir) — element ↔ TipTap JSON conversion
- `ContentUtils` — HTML sanitization for client-sent content
- `serialization.js` — `docToElements()` / `elementsToDoc()` (snake_case ↔ camelCase type mapping)
- `LiveViewBridge` extension — debounced client↔server sync (500ms), `suppressUpdate` flag for server echoes
- `ScreenplayKeymap` — Enter (next type inference), Tab/Shift-Tab (cycle), Backspace (delete/convert), Escape
- `AutoDetectRules` — InputRules for INT./EXT., transitions, parentheticals, ALL CAPS
- `ContdPlugin` — ProseMirror decoration for CONT'D badges
- `TransitionAlignPlugin` — decoration for left-aligned "FADE IN:" transitions
- `ScreenplayPlaceholder` — per-type placeholder text
- `builders/` — vanilla JS DOM builders for interactive NodeViews (condition, instruction, response)
- Rich text serialization — bold, italic, strike marks + mention inline nodes survive round-trips

### Post-Audit Fixes

**After:** TipTap Phase 3

Addressed 10 of 18 audit findings. Removed dead `@continuations` server computation (now client-side via ContdPlugin). Added `ContentUtils.sanitize_html/1` to `sync_editor_content` path. Fixed new-element ordering bug in `reorder_after_sync`. Extracted `suppressedDispatch` JS helper. Removed dead CSS (`.screenplay-element`, duplicate `.mention`, legacy read-mode rules). Fixed stale comment referencing deleted file.

---

## Architecture

### Entity Relationship

```
Project
├── Sheets (data/variables)
├── Flows (visual graph)
└── Screenplays (formatted script)
    ├── linked_flow_id (optional FK → flows)
    └── ScreenplayElement[] (ordered blocks)
```

### File Structure

```
lib/storyarn/
├── screenplays.ex                              # Context facade (defdelegate)
├── screenplays/
│   ├── screenplay.ex                           # Schema (6 changesets, draft fields)
│   ├── screenplay_element.ex                   # Schema (16 element types, 4 changesets)
│   ├── screenplay_crud.ex                      # CRUD + tree listing + soft-delete
│   ├── element_crud.ex                         # Element CRUD + reorder + split
│   ├── screenplay_queries.ex                   # Read-only queries
│   ├── tree_operations.ex                      # Sidebar tree reordering
│   ├── element_grouping.ex                     # Computed dialogue groups + continuations
│   ├── character_extension.ex                  # Parse V.O., O.S., CONT'D
│   ├── auto_detect.ex                          # Pattern matching (server-side fallback)
│   ├── content_utils.ex                        # HTML sanitization
│   ├── tiptap_serialization.ex                 # Element ↔ TipTap JSON
│   ├── flow_sync.ex                            # Bidirectional sync engine
│   ├── node_mapping.ex                         # Element → flow node attrs (pure)
│   ├── reverse_node_mapping.ex                 # Flow node → element attrs (pure)
│   ├── flow_traversal.ex                       # DFS graph linearization (pure)
│   ├── flow_layout.ex                          # Tree-aware auto-layout (pure)
│   ├── linked_page_crud.ex                     # Linked page CRUD
│   └── page_tree_builder.ex                    # Page tree → flat nodes (pure)

lib/storyarn_web/
├── live/screenplay_live/
│   ├── index.ex                                # List/tree view
│   ├── show.ex                                 # Editor (thin dispatcher to TipTap)
│   └── form.ex                                 # Create modal (LiveComponent)
├── components/
│   └── sidebar/screenplay_tree.ex              # Sidebar tree component

assets/js/
├── hooks/
│   ├── screenplay_editor.js                    # Single LiveView hook for TipTap
│   └── dialogue_screenplay_editor.js           # Flow editor's dialogue fullscreen editor
├── screenplay/
│   ├── serialization.js                        # docToElements / elementsToDoc
│   ├── character_sheet_picker.js               # Character sheet floating picker
│   ├── utils.js                                # Shared utilities
│   ├── nodes/
│   │   ├── index.js                            # Re-exports all nodes
│   │   ├── base_attrs.js                       # Shared elementId + data attributes
│   │   ├── create_text_node.js                 # Factory for text block nodes
│   │   ├── screenplay_doc.js                   # Custom doc node (content: screenplayBlock+)
│   │   ├── scene_heading.js                    # Text block
│   │   ├── action.js                           # Text block (default type)
│   │   ├── character.js                        # Text block + sheet reference
│   │   ├── dialogue.js                         # Text block
│   │   ├── parenthetical.js                    # Text block
│   │   ├── transition.js                       # Text block
│   │   ├── note.js                             # Text block
│   │   ├── section.js                          # Text block
│   │   ├── page_break.js                       # Atom
│   │   ├── hub_marker.js                       # Atom + NodeView
│   │   ├── jump_marker.js                      # Atom + NodeView
│   │   ├── title_page.js                       # Atom + NodeView
│   │   ├── conditional.js                      # Atom + NodeView (condition builder)
│   │   ├── instruction.js                      # Atom + NodeView (instruction builder)
│   │   ├── response.js                         # Atom + NodeView (choices + linked pages)
│   │   └── dual_dialogue.js                    # Atom + NodeView (two-column layout)
│   ├── extensions/
│   │   ├── screenplay_keymap.js                # Enter/Tab/Backspace/Escape
│   │   ├── slash_commands.js                   # / command palette (Suggestion API)
│   │   ├── slash_menu_renderer.js              # Floating menu DOM (vanilla JS)
│   │   ├── liveview_bridge.js                  # Debounced client↔server sync
│   │   ├── auto_detect_rules.js                # InputRules for type detection
│   │   ├── screenplay_placeholder.js           # Per-type placeholder text
│   │   ├── contd_plugin.js                     # CONT'D decorations
│   │   ├── transition_align_plugin.js          # Left-align "FADE IN:" etc.
│   │   └── create_decoration_plugin.js         # Decoration plugin factory
│   └── builders/
│       ├── interactive_header.js               # Shared header for atom NodeViews
│       ├── condition_builder_core.js           # Condition builder DOM
│       ├── instruction_builder_core.js         # Instruction builder DOM
│       ├── response_builder.js                 # Response choices DOM
│       └── utils.js                            # Builder utilities

assets/css/
└── screenplay.css                              # Industry-standard formatting + all UI
```

### Test Structure

```
test/storyarn/screenplays/
├── screenplay_test.exs                         # Schema validations
├── screenplay_element_test.exs                 # Element schema + types
├── screenplay_crud_test.exs                    # CRUD operations
├── element_crud_test.exs                       # Element CRUD + reordering + splitting
├── element_grouping_test.exs                   # Grouping + continuations
├── character_extension_test.exs                # V.O., O.S., CONT'D parsing
├── auto_detect_test.exs                        # Pattern matching
├── content_utils_test.exs                      # HTML sanitization
├── tiptap_serialization_test.exs               # Element ↔ TipTap JSON round-trips
├── node_mapping_test.exs                       # Element → flow node
├── reverse_node_mapping_test.exs               # Flow node → element
├── flow_traversal_test.exs                     # DFS linearization
├── flow_sync_test.exs                          # Bidirectional sync
├── flow_layout_test.exs                        # Auto-layout
├── linked_page_crud_test.exs                   # Linked pages
├── page_tree_builder_test.exs                  # Page tree builder
├── screenplay_queries_test.exs                 # Queries
└── tree_operations_test.exs                    # Tree reordering

test/storyarn_web/live/screenplay_live/
├── index_test.exs                              # Sidebar, create, delete
└── show_test.exs                               # Editor sync, interactive blocks, flow sync
```

---

## Phase 10: Title Page & Export (Pending)

### 10.1 Title Page Block

The `title_page` TipTap atom node already exists (`assets/js/screenplay/nodes/title_page.js`) and renders as a stub badge. This task makes it a full editing NodeView.

**Data structure:**
```elixir
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

**Visual rendering (centered, industry-standard):**
```
                 LA TABERNA DEL CUERVO

                      Written by

                      Studio Dev


                                    Draft: February 2026
                                    Contact: studio@example.com
```

**Implementation:**
1. Update `title_page.js` NodeView to render editable fields (title, credit, author, draft_date, contact)
2. Each field is an `<input>` or `<textarea>` inside the NodeView
3. On blur, dispatch event → hook → `pushEvent("update_title_page", %{element_id, data})`
4. Add `handle_event("update_title_page", ...)` to `show.ex`
5. CSS for centered title page layout in `screenplay.css`

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

**Implementation:**
1. Create `lib/storyarn/screenplays/export/fountain.ex`
2. Add `export_fountain/1` delegate to `screenplays.ex`
3. Add download route/handler in `show.ex` (toolbar button → download `.fountain` file)
4. Handle dual_dialogue export (Fountain `^` syntax for dual dialogue)
5. Handle rich text → plain text conversion (strip HTML tags, preserve text)
6. Tests: round-trip coverage for all element types

### 10.3 PDF Export (Future)

Use a PDF rendering library to generate properly formatted screenplay PDFs. Deferred.

### 10.4 Import from Fountain

Parse `.fountain` files into screenplay elements. Use the Fountain spec to detect element types from text patterns.

**Implementation:**
1. Create `lib/storyarn/screenplays/import/fountain.ex`
2. Fountain parser: split on blank lines, apply type detection rules
3. Add upload UI in toolbar or create modal
4. Tests: parse sample `.fountain` files, verify element types and content

---

## Deferred Features

### Collaboration (Edge Case H)

Flows and Sheets have real-time collaboration (presence, locks, cursors). The screenplay editor is a single TipTap instance, so collaboration requires a different approach:

- **Option A — Document-level locking:** Only one user can edit at a time. Others see read-only mode with presence indicators. Simplest, matches the "one writer" screenwriting convention.
- **Option B — ProseMirror collaboration:** Use `prosemirror-collab` or Yjs for real-time multi-user editing within the single TipTap instance. Complex but seamless.

The existing `Collaboration` module (presence, topic subscription) can be reused for presence. The locking/collaboration mechanism needs design work.

### Nested Conditionals (Edge Case G)

Conditionals with nested true/false element branches (`depth` + `branch` fields). The flat list model supports arbitrary nesting. Condition nodes currently sync their data but connect linearly. Implementing visual nesting in TipTap would require either:
- Nested document structure (ProseMirror wrapping nodes)
- Virtual nesting via decorations + indentation

### Structural Undo/Redo

TipTap provides text-level undo/redo natively via the History extension (included in StarterKit). Structural operations that bypass TipTap (e.g., server-side flow sync replacing all elements) are not covered. A session-level operation log could be added if needed.

---

## Key Design Decisions

### D1: Flat element list

Flat list with `position` ordering. Simpler database queries, easier reordering, matches how flow nodes work. Nesting is a rendering concern only.

### D2: Single TipTap instance

One TipTap `Editor` instance for the entire document. Every element type is a custom `Node.create()` extension. Text blocks use `content: "inline*"`. Interactive/utility blocks are atom NodeViews. This gives continuous cursor flow, native keyboard navigation, consistent styling, and TipTap-native undo/redo.

### D3: Manual sync trigger

User controls when the flow is updated from the screenplay and vice versa. Auto-sync on every edit would be expensive and disruptive.

### D4: Computed dialogue groups (no stored group_id)

Groups computed from element adjacency at runtime in `ElementGrouping`. O(n), trivial for typical element counts, impossible to become inconsistent.

### D5: Diff-based sync

Both `sync_to_flow` and `sync_from_flow` use diff (update existing, create new, delete orphaned). Preserves manual flow canvas positions and non-mappeable screenplay elements.

### D6: Flow node `source` field

`source` ("manual" | "screenplay_sync") on `flow_nodes` tracks sync ownership. Sync operations only touch nodes they created.

### D7: Draft fields in schema from day one

`draft_of_id`, `draft_label`, `draft_status` included but unused. Prevents migration breakage when drafts are implemented. See FUTURE_FEATURES.md.

---

## Dependencies

- **Existing:** Condition builder, instruction builder, variable system, Collaboration module (presence + locks)
- **npm (already installed):** `@tiptap/core`, `@tiptap/starter-kit`, `@tiptap/extension-mention`, `@tiptap/suggestion`, `@tiptap/pm`, `@tiptap/extension-placeholder`
- **Migration done:** `add_source_to_flow_nodes` — `source` field for sync ownership
- **Lucide icons:** `scroll-text`, `clapperboard`, `align-left`, `columns-2`, `parentheses`, `scissors`
- **Future:** Draft system fields in schema but not implemented — see FUTURE_FEATURES.md
