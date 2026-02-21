# Undo/Redo System — Draft

## Current State

Storyarn has a **version history** system (`Sheets.Versioning`) that creates snapshots every 5 minutes. This is not undo/redo — it's manual recovery for collaborative editing.

**There is no per-action undo/redo.**

## Goal

Implement Cmd+Z / Cmd+Shift+Z (undo/redo) for sheet editing operations, including:
- Cell value changes
- Column type changes (with cell value reset/restore)
- Column add/delete
- Row add/delete
- Column/row rename
- Block add/delete/reorder
- Config changes (constant toggle, collapse, etc.)

## Proposed Architecture

### Command Pattern

Each user action creates a **Command** struct stored in a per-session undo stack:

```elixir
defmodule Storyarn.Sheets.Command do
  @type t :: %__MODULE__{
    id: String.t(),
    type: atom(),
    timestamp: NaiveDateTime.t(),
    data: map(),       # forward operation params
    undo_data: map()   # reverse operation params
  }
end
```

### Example Commands

**Cell update:**
```elixir
%Command{
  type: :update_cell,
  data: %{row_id: 1, column_slug: "health", value: "50"},
  undo_data: %{row_id: 1, column_slug: "health", value: "100"}  # previous value
}
```

**Column type change:**
```elixir
%Command{
  type: :change_column_type,
  data: %{column_id: 1, new_type: "text"},
  undo_data: %{column_id: 1, old_type: "number", old_cells: %{row_1: "50", row_2: "100"}}
}
```

**Column delete:**
```elixir
%Command{
  type: :delete_column,
  data: %{column_id: 1},
  undo_data: %{column: %{name: "Health", type: "number", ...}, cells: %{...}}
}
```

### Stack Management

```elixir
defmodule Storyarn.Sheets.UndoStack do
  @max_stack_size 50

  defstruct undo: [], redo: []

  def push(stack, command)    # push to undo, clear redo
  def undo(stack)             # pop undo, push to redo, return command
  def redo(stack)             # pop redo, push to undo, return command
  def clear(stack)            # reset both stacks
end
```

### LiveView Integration

Store the undo stack in socket assigns per-session:

```elixir
# In content_tab.ex mount
|> assign(:undo_stack, %UndoStack{})

# Before each operation, capture undo_data
# After operation, push command to stack

# Handle keyboard shortcuts via JS hook
def handle_event("undo", _params, socket) do
  case UndoStack.undo(socket.assigns.undo_stack) do
    {:ok, command, new_stack} ->
      socket = execute_undo(socket, command)
      {:noreply, assign(socket, :undo_stack, new_stack)}
    :empty ->
      {:noreply, socket}
  end
end
```

### JS Hook for Keyboard Shortcuts

```javascript
// hooks/undo_redo.js
export default {
  mounted() {
    this.handleKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "z") {
        e.preventDefault()
        if (e.shiftKey) {
          this.pushEvent("redo", {})
        } else {
          this.pushEvent("undo", {})
        }
      }
    }
    document.addEventListener("keydown", this.handleKeydown)
  },
  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown)
  }
}
```

## Key Decisions Needed

1. **Scope**: Per-sheet? Per-block? Per-table?
2. **Collaboration**: What happens when User A undoes while User B is editing?
3. **Stack size**: How many operations to keep? (proposed: 50)
4. **Persistence**: In-memory only (lost on disconnect) or persisted?
5. **Granularity**: Group rapid edits (debounce cell typing)?

## Implementation Order

1. Define `Command` struct and `UndoStack` module
2. Add JS hook for Cmd+Z / Cmd+Shift+Z
3. Integrate with table cell updates (simplest case)
4. Extend to column/row CRUD operations
5. Extend to block-level operations
6. Add collaboration conflict handling

## Complexity Estimate

- Core undo stack module: Small
- Per-operation command capture: Medium (each handler needs before/after state)
- Column type change with cell restore: Medium (need to snapshot all cell values before reset)
- Collaboration conflicts: Large (deferred — start with single-user undo)
