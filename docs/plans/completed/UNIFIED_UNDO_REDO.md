# Unified Undo/Redo System — Sheet Implementation + Shared Infrastructure

> **Goal:** Implement undo/redo for the Sheet editor, extract a shared Elixir helper module to DRY up Maps ↔ Sheets, and unify keyboard shortcut handling across all three editors (Maps, Flows, Sheets).
>
> **Priority:** High — Sheets is the only editor without undo/redo
>
> **Last Updated:** February 22, 2026

---

## Table of Contents

1. [Current State Analysis](#1-current-state-analysis)
2. [Architecture Decision: Server-Side for Sheets](#2-architecture-decision-server-side-for-sheets)
3. [Phase 0 — Shared Infrastructure](#phase-0--shared-infrastructure)
4. [Phase 1 — Sheet Metadata Operations](#phase-1--sheet-metadata-operations)
5. [Phase 2 — Block CRUD Operations](#phase-2--block-crud-operations)
6. [Phase 3 — Block Value & Config Edits](#phase-3--block-value--config-edits)
7. [Phase 4 — Table Block Operations](#phase-4--table-block-operations)
8. [Phase 5 — Compound & Complex Actions](#phase-5--compound--complex-actions)
9. [Phase 6 — Keyboard Shortcut Unification](#phase-6--keyboard-shortcut-unification)
10. [Files Modified Summary](#files-modified-summary)
11. [Testing Strategy](#testing-strategy)
12. [Future Considerations](#future-considerations)

---

## 1. Current State Analysis

### 1.1 Maps — Server-Side Undo/Redo (Fully Implemented)

| Aspect                 | Detail                                                                                     |
|------------------------|--------------------------------------------------------------------------------------------|
| **Architecture**       | Server-side stacks in socket assigns (`undo_stack`, `redo_stack`)                          |
| **Module**             | `StoryarnWeb.MapLive.Handlers.UndoRedoHandlers`                                            |
| **Action format**      | Tagged tuples: `{:create_pin, pin}`, `{:move_pin, id, prev, new}`, etc.                    |
| **Stack cap**          | 50 entries (`@max_undo 50`)                                                                |
| **Coalescing**         | Yes — `push_undo_coalesced/2` for move operations                                          |
| **Compound actions**   | Yes — `{:compound, [sub_actions]}` with reverse-order undo                                 |
| **ID rebasing**        | Yes — `rebase_ids/2`, `track_rebased_id/3` for post-recreation ID mapping                  |
| **Deletion model**     | Hard-delete + full struct storage for recreation                                           |
| **Keyboard shortcuts** | `map_canvas.js` hook: `Cmd+Z` → `pushEvent("undo")`, `Cmd+Shift+Z/Y` → `pushEvent("redo")` |
| **Test coverage**      | 750+ lines in `undo_redo_test.exs`                                                         |
| **Collaboration**      | No per-user awareness                                                                      |

**Key functions in `UndoRedoHandlers`:**
- `push_undo/2` — pushes action, clears redo stack
- `push_undo_no_clear/2` — pushes without clearing redo (used during redo)
- `push_redo/2` — pushes to redo stack
- `push_undo_coalesced/2` — merges consecutive same-element moves
- `handle_undo/2` — pops undo stack, dispatches `undo_action/2`, pushes to redo
- `handle_redo/2` — pops redo stack, dispatches `redo_action/2`, pushes to undo
- `*_to_attrs/1` — attribute extraction helpers for element recreation

### 1.2 Flows — Client-Side Undo/Redo (Partially Implemented)

| Aspect                 | Detail                                                                                                                                                        |
|------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Architecture**       | Client-side JS via `rete-history-plugin` + custom `history_preset.js`                                                                                         |
| **Action classes**     | `DragAction`, `AddConnectionAction`, `RemoveConnectionAction`, `DeleteNodeAction`, `CreateNodeAction`, `FlowMetaAction`, `NodeDataAction`, `AutoLayoutAction` |
| **Server events**      | `restore_node`, `restore_node_data`, `restore_flow_meta` (in `node_helpers.ex`, `generic_node_handlers.ex`)                                                   |
| **Coalescing**         | Yes — `NODE_DATA_COALESCE_MS = 1000`, `FLOW_META_COALESCE_MS = 2000`                                                                                          |
| **Guards**             | `isLoadingFromServer` counter, `_historyTriggeredDelete` flag, `data.self` collaboration flag                                                                 |
| **Deletion model**     | Soft-delete (`deleted_at` column) — IDs preserved                                                                                                             |
| **Keyboard shortcuts** | `keyboard_handler.js`: same shortcuts, with `isEditable()` guard                                                                                              |

**Why different from Maps:** The flow editor is built on Rete.js which manages its own client-side state (nodes, connections, positions). The JS history integrates naturally with Rete's pipe system. Converting to server-side would fight the framework.

### 1.3 Sheets — No Undo/Redo (Not Implemented)

| Aspect                 | Detail                                                                                        |
|------------------------|-----------------------------------------------------------------------------------------------|
| **Deletion model**     | Hard-delete (`Repo.delete()`) — no `deleted_at` column                                        |
| **Versioning**         | `Sheets.Versioning` creates snapshots every 5 minutes (not per-action undo)                   |
| **State management**   | Changes go directly to DB, socket reloaded after each operation                               |
| **Keyboard shortcuts** | None for undo/redo                                                                            |
| **Main handlers**      | `block_crud_handlers.ex`, `table_handlers.ex`, `config_helpers.ex`, `inheritance_handlers.ex` |

---

## 2. Architecture Decision: Server-Side for Sheets

**Decision: Use the Maps pattern (server-side stacks in socket assigns).**

**Rationale:**
1. Sheets use standard Phoenix LiveView forms and events — no JS framework like Rete.js
2. All mutations already go through the server (no client-side state to track)
3. Server-side approach is simpler — no JS action classes, no loading guards, no self-flag
4. Consistent with Maps — enables shared Elixir helpers
5. Maps' pattern is battle-tested with 750+ lines of tests

**Key difference from Maps:** Sheets don't need ID rebasing because blocks use UUIDs (not auto-increment integers), so re-created blocks can keep their original UUIDs if we store them.

---

## Phase 0 — Shared Infrastructure

### 0.1 Extract `UndoRedoStack` Helper Module

Create a shared module that extracts the generic stack management logic used by both Maps and Sheets.

**File:** `lib/storyarn_web/helpers/undo_redo_stack.ex`

```elixir
defmodule StoryarnWeb.Helpers.UndoRedoStack do
  @moduledoc """
  Shared undo/redo stack management for LiveView editors.

  Provides generic stack operations (push, pop, coalesce, cap) that can be
  used by any LiveView that needs undo/redo functionality. Domain-specific
  action dispatch (undo_action/redo_action) remains in each editor's handler.
  """

  import Phoenix.Component, only: [assign: 2]

  @default_max_size 50

  @doc """
  Initializes undo/redo assigns on a socket.
  Call in the LiveView's mount/3 or handle_params/3.
  """
  def init(socket) do
    assign(socket, undo_stack: [], redo_stack: [])
  end

  @doc """
  Pushes an action onto the undo stack and clears the redo stack.
  Used when the user performs a new action (invalidates redo history).
  """
  def push_undo(socket, action, max_size \\ @default_max_size) do
    stack = Enum.take([action | socket.assigns.undo_stack], max_size)
    assign(socket, undo_stack: stack, redo_stack: [])
  end

  @doc """
  Pushes an action onto the undo stack WITHOUT clearing the redo stack.
  Used internally during redo to preserve the remaining redo history.
  """
  def push_undo_no_clear(socket, action, max_size \\ @default_max_size) do
    stack = Enum.take([action | socket.assigns.undo_stack], max_size)
    assign(socket, :undo_stack, stack)
  end

  @doc """
  Pushes an action onto the redo stack.
  """
  def push_redo(socket, action, max_size \\ @default_max_size) do
    stack = Enum.take([action | socket.assigns.redo_stack], max_size)
    assign(socket, :redo_stack, stack)
  end

  @doc """
  Coalesces consecutive actions of the same type and element.
  If the top of the undo stack matches the `match_fn`, replaces it with
  the `merge_fn` result. Otherwise pushes as a normal new action.

  ## Example

      push_coalesced(socket, action,
        fn top -> match?(^action_type, elem(top, 0)) and elem(top, 1) == id end,
        fn top -> put_elem(top, 3, new_value) end
      )
  """
  def push_coalesced(socket, action, match_fn, merge_fn, max_size \\ @default_max_size) do
    case socket.assigns.undo_stack do
      [top | rest] ->
        if match_fn.(top) do
          updated = merge_fn.(top)
          assign(socket, undo_stack: [updated | rest], redo_stack: [])
        else
          push_undo(socket, action, max_size)
        end

      _ ->
        push_undo(socket, action, max_size)
    end
  end

  @doc """
  Pops from the undo stack and returns `{action, updated_socket}` or `:empty`.
  Does NOT execute the action — the caller must dispatch it.
  """
  def pop_undo(socket) do
    case socket.assigns.undo_stack do
      [] -> :empty
      [action | rest] -> {action, assign(socket, :undo_stack, rest)}
    end
  end

  @doc """
  Pops from the redo stack and returns `{action, updated_socket}` or `:empty`.
  """
  def pop_redo(socket) do
    case socket.assigns.redo_stack do
      [] -> :empty
      [action | rest] -> {action, assign(socket, :redo_stack, rest)}
    end
  end

  @doc """
  Clears both stacks (e.g., after a full data refresh that invalidates history).
  """
  def clear(socket) do
    assign(socket, undo_stack: [], redo_stack: [])
  end

  @doc """
  Returns true if undo stack is non-empty.
  """
  def can_undo?(socket), do: socket.assigns.undo_stack != []

  @doc """
  Returns true if redo stack is non-empty.
  """
  def can_redo?(socket), do: socket.assigns.redo_stack != []
end
```

### 0.2 Refactor Maps to Use Shared Module

Refactor `StoryarnWeb.MapLive.Handlers.UndoRedoHandlers` to delegate stack operations to the shared module. The domain-specific `undo_action/2` and `redo_action/2` dispatch functions remain in the maps handler.

**Changes to `undo_redo_handlers.ex`:**

```elixir
# Replace local stack functions with:
alias StoryarnWeb.Helpers.UndoRedoStack

# push_undo/2 → UndoRedoStack.push_undo/2
# push_redo/2 → UndoRedoStack.push_redo/2
# push_undo_no_clear/2 → UndoRedoStack.push_undo_no_clear/2
# push_undo_coalesced/2 → keep as local wrapper using UndoRedoStack.push_coalesced/4

# handle_undo pattern:
def handle_undo(_params, socket) do
  case UndoRedoStack.pop_undo(socket) do
    :empty ->
      {:noreply, socket}

    {action, socket} ->
      case undo_action(action, socket) do
        {:ok, socket, redo_item} ->
          {:noreply,
           socket
           |> UndoRedoStack.push_redo(redo_item)
           |> reload_map()}

        {:error, socket} ->
          {:noreply, socket}
      end
  end
end
```

**Backward compatibility:** The public API (`push_undo/2`, etc.) called from `element_handlers.ex` and `layer_handlers.ex` should continue to work. Either:
- Keep the local functions as wrappers that delegate to the shared module, OR
- Update all call sites to use `UndoRedoStack.push_undo(socket, action)`

**Recommended:** Keep local wrappers in `UndoRedoHandlers` that delegate to the shared module. This avoids touching every handler file and keeps the domain-specific coalescing logic local.

### 0.3 JS Keyboard Hook for Sheets

**File:** `assets/js/hooks/undo_redo.js`

```javascript
/**
 * Generic undo/redo keyboard shortcut hook.
 * Attach to any container element to enable Cmd+Z / Cmd+Shift+Z / Cmd+Y.
 * Skips when focus is in editable fields (inputs, textareas, contenteditable).
 */
const UndoRedo = {
  mounted() {
    this.handleKeydown = (e) => {
      const mod = e.metaKey || e.ctrlKey;
      if (!mod) return;

      // Skip when editing in form fields
      const tag = e.target.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      if (e.target.isContentEditable) return;

      if (e.key === "z" && !e.shiftKey) {
        e.preventDefault();
        this.pushEvent("undo", {});
      } else if (e.key === "z" && e.shiftKey) {
        e.preventDefault();
        this.pushEvent("redo", {});
      } else if (e.key === "y") {
        e.preventDefault();
        this.pushEvent("redo", {});
      }
    };

    document.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown);
  },
};

export default UndoRedo;
```

**Register in `app.js`:**

```javascript
import UndoRedo from "./hooks/undo_redo";

const Hooks = {
  // ... existing hooks
  UndoRedo,
};
```

**Note:** Maps and Flows already have their own keyboard handling embedded in their respective hooks (`map_canvas.js`, `keyboard_handler.js`). The new `UndoRedo` hook is specifically for Sheets and any future editor that doesn't have its own keyboard handler. We do NOT refactor existing editors to use this hook — that would be disruptive for no gain.

---

## Phase 1 — Sheet Metadata Operations

### 1.1 Action Types

| Action Tuple                                            | Trigger                                       | Undo                  | Redo                 |
|---------------------------------------------------------|-----------------------------------------------|-----------------------|----------------------|
| `{:update_sheet_name, prev_name, new_name}`             | `set_sheet_name`                              | Restore prev_name     | Restore new_name     |
| `{:update_sheet_shortcut, prev_shortcut, new_shortcut}` | `set_sheet_shortcut`                          | Restore prev_shortcut | Restore new_shortcut |
| `{:update_sheet_color, prev_color, new_color}`          | `set_sheet_color` / `clear_sheet_color`       | Restore prev_color    | Restore new_color    |
| `{:update_sheet_description, prev_desc, new_desc}`      | `set_sheet_description`                       | Restore prev_desc     | Restore new_desc     |
| `{:update_sheet_avatar, prev_asset_id, new_asset_id}`   | `upload_sheet_avatar` / `remove_sheet_avatar` | Restore prev_asset_id | Restore new_asset_id |
| `{:update_sheet_banner, prev_asset_id, new_asset_id}`   | `upload_sheet_banner` / `remove_sheet_banner` | Restore prev_asset_id | Restore new_asset_id |

### 1.2 Implementation Pattern

**Handler modification** (in `show.ex` or relevant component):

```elixir
# Before:
def handle_event("set_sheet_name", %{"name" => name}, socket) do
  sheet = socket.assigns.sheet
  case Sheets.update_sheet(sheet, %{name: name}) do
    {:ok, updated} -> {:noreply, assign(socket, :sheet, updated)}
    {:error, _} -> {:noreply, socket}
  end
end

# After:
def handle_event("set_sheet_name", %{"name" => name}, socket) do
  sheet = socket.assigns.sheet
  prev_name = sheet.name

  case Sheets.update_sheet(sheet, %{name: name}) do
    {:ok, updated} ->
      {:noreply,
       socket
       |> assign(:sheet, updated)
       |> UndoRedoStack.push_undo({:update_sheet_name, prev_name, name})}

    {:error, _} ->
      {:noreply, socket}
  end
end
```

### 1.3 Undo/Redo Dispatch

**File:** `lib/storyarn_web/live/sheet_live/handlers/undo_redo_handlers.ex` (NEW)

```elixir
defmodule StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers do
  @moduledoc """
  Undo/redo action dispatch for the Sheet editor.
  Uses shared stack management from UndoRedoStack.
  """

  alias StoryarnWeb.Helpers.UndoRedoStack
  alias Storyarn.Sheets

  def handle_undo(_params, socket) do
    case UndoRedoStack.pop_undo(socket) do
      :empty -> {:noreply, socket}
      {action, socket} ->
        case undo_action(action, socket) do
          {:ok, socket, redo_item} ->
            {:noreply,
             socket
             |> UndoRedoStack.push_redo(redo_item)
             |> reload_sheet()}
          {:error, socket} ->
            {:noreply, socket}
        end
    end
  end

  def handle_redo(_params, socket) do
    case UndoRedoStack.pop_redo(socket) do
      :empty -> {:noreply, socket}
      {action, socket} ->
        case redo_action(action, socket) do
          {:ok, socket, undo_item} ->
            {:noreply,
             socket
             |> UndoRedoStack.push_undo_no_clear(undo_item)
             |> reload_sheet()}
          {:error, socket} ->
            {:noreply, socket}
        end
    end
  end

  # --- Sheet metadata ---

  defp undo_action({:update_sheet_name, prev, _new}, socket) do
    case Sheets.update_sheet(socket.assigns.sheet, %{name: prev}) do
      {:ok, _} -> {:ok, socket, {:update_sheet_name, prev, socket.assigns.sheet.name}}
      {:error, _} -> {:error, socket}
    end
  end

  defp redo_action({:update_sheet_name, _prev, new}, socket) do
    case Sheets.update_sheet(socket.assigns.sheet, %{name: new}) do
      {:ok, _} -> {:ok, socket, {:update_sheet_name, socket.assigns.sheet.name, new}}
      {:error, _} -> {:error, socket}
    end
  end

  # ... same pattern for shortcut, color, description, avatar, banner

  defp reload_sheet(socket) do
    # Re-fetch sheet with all associations from database
    sheet = Sheets.get_sheet!(socket.assigns.sheet.id)
    assign(socket, :sheet, sheet)
    # Also reload blocks if needed
  end
end
```

### 1.4 Coalescing for Name/Shortcut/Description

Name and description edits should coalesce within a time window. Since the server doesn't have a timer-based coalescing mechanism (unlike JS), we use the Maps approach: **coalesce by matching the top of the stack**.

```elixir
# For sheet name edits, if the top of the stack is also a name edit, merge:
def push_name_coalesced(socket, prev, new) do
  UndoRedoStack.push_coalesced(
    socket,
    {:update_sheet_name, prev, new},
    fn {:update_sheet_name, _, _} -> true; _ -> false end,
    fn {:update_sheet_name, original_prev, _} -> {:update_sheet_name, original_prev, new} end
  )
end
```

This ensures typing "H", "He", "Hel", "Hell", "Hello" produces a single undo entry "original → Hello" instead of five entries.

---

## Phase 2 — Block CRUD Operations

### 2.1 Action Types

| Action Tuple                                     | Trigger                | Undo                    | Redo                    |
|--------------------------------------------------|------------------------|-------------------------|-------------------------|
| `{:create_block, block_snapshot}`                | `add_block`            | Delete the block        | Re-create from snapshot |
| `{:delete_block, block_snapshot}`                | `delete_block`         | Re-create from snapshot | Delete again            |
| `{:reorder_blocks, prev_order, new_order}`       | `reorder`              | Apply prev_order        | Apply new_order         |
| `{:reorder_with_columns, prev_items, new_items}` | `reorder_with_columns` | Apply prev_items        | Apply new_items         |
| `{:create_column_group, block_ids, group_id}`    | `create_column_group`  | Remove column group     | Re-create column group  |

### 2.2 Block Snapshot Format

For undo of block deletion, we need to store enough data to recreate the block:

```elixir
defp block_to_snapshot(block) do
  %{
    id: block.id,
    sheet_id: block.sheet_id,
    type: block.type,
    label: block.label,
    value: block.value,
    config: block.config,
    position: block.position,
    is_constant: block.is_constant,
    variable_name: block.variable_name,
    scope: block.scope,
    column_group_id: block.column_group_id,
    column_index: block.column_index,
    source_block_id: block.source_block_id,
    hidden_for_children: block.hidden_for_children
  }
end
```

### 2.3 Create Block — Recording

```elixir
def handle_event("add_block", %{"type" => type}, socket) do
  # ... existing create logic ...
  case Sheets.create_block(socket.assigns.sheet, attrs) do
    {:ok, block} ->
      {:noreply,
       socket
       |> UndoRedoStack.push_undo({:create_block, block_to_snapshot(block)})
       |> reload_blocks()}
    {:error, _} ->
      {:noreply, socket}
  end
end
```

### 2.4 Delete Block — Recording

```elixir
def handle_event("delete_block", %{"id" => block_id}, socket) do
  block = Sheets.get_block!(block_id)
  snapshot = block_to_snapshot(block)

  case Sheets.delete_block(block) do
    {:ok, _} ->
      {:noreply,
       socket
       |> UndoRedoStack.push_undo({:delete_block, snapshot})
       |> reload_blocks()}
    {:error, _} ->
      {:noreply, socket}
  end
end
```

### 2.5 Undo/Redo Dispatch for Block CRUD

```elixir
# Undo create = delete the block
defp undo_action({:create_block, snapshot}, socket) do
  case Sheets.get_block(snapshot.id) do
    nil -> {:error, socket}  # already deleted
    block ->
      case Sheets.delete_block(block) do
        {:ok, _} -> {:ok, socket, {:create_block, snapshot}}
        {:error, _} -> {:error, socket}
      end
  end
end

# Undo delete = re-create the block from snapshot
defp undo_action({:delete_block, snapshot}, socket) do
  case Sheets.create_block_from_snapshot(socket.assigns.sheet, snapshot) do
    {:ok, block} ->
      {:ok, socket, {:delete_block, block_to_snapshot(block)}}
    {:error, _} ->
      {:error, socket}
  end
end

# Undo reorder = apply previous order
defp undo_action({:reorder_blocks, prev_order, new_order}, socket) do
  case Sheets.reorder_blocks(socket.assigns.sheet.id, prev_order) do
    :ok -> {:ok, socket, {:reorder_blocks, prev_order, new_order}}
    {:error, _} -> {:error, socket}
  end
end
```

### 2.6 New Context Function: `Sheets.create_block_from_snapshot/2`

The Sheets context needs a new function to recreate a block with a specific ID and all attributes from a snapshot:

```elixir
def create_block_from_snapshot(sheet, snapshot) do
  attrs = Map.from_struct(snapshot) |> Map.drop([:id, :sheet_id])

  %Block{id: snapshot.id, sheet_id: sheet.id}
  |> Block.changeset(attrs)
  |> Repo.insert(on_conflict: :nothing)  # idempotent for redo safety
end
```

**Alternative (if UUIDs are preserved):** Use `Repo.insert()` with the original UUID. Since PostgreSQL supports inserting with a specific UUID, the block will get its original ID back, avoiding any ID rebasing issues.

---

## Phase 3 — Block Value & Config Edits

### 3.1 Action Types

| Action Tuple                                                   | Trigger                                | Undo                 | Redo                |
|----------------------------------------------------------------|----------------------------------------|----------------------|---------------------|
| `{:update_block_value, block_id, prev_value, new_value}`       | `update_block_value`                   | Restore prev_value   | Restore new_value   |
| `{:update_block_config, block_id, prev_config, new_config}`    | `save_block_config`                    | Restore prev_config  | Restore new_config  |
| `{:toggle_constant, block_id, prev_value, new_value}`          | `toggle_constant`                      | Toggle back          | Toggle forward      |
| `{:update_rich_text, block_id, prev_content, new_content}`     | `update_rich_text`                     | Restore prev_content | Restore new_content |
| `{:set_boolean_block, block_id, prev_value, new_value}`        | `set_boolean_block`                    | Restore prev         | Restore new         |
| `{:select_reference, block_id, prev_ref, new_ref}`             | `select_reference` / `clear_reference` | Restore prev_ref     | Restore new_ref     |
| `{:toggle_multi_select, block_id, prev_value, new_value}`      | `toggle_multi_select`                  | Restore prev         | Restore new         |
| `{:add_select_option, block_id, prev_options, new_options}`    | `add_select_option`                    | Restore prev_options | Restore new_options |
| `{:remove_select_option, block_id, prev_options, new_options}` | `remove_select_option`                 | Restore prev         | Restore new         |
| `{:update_select_option, block_id, prev_options, new_options}` | `update_select_option`                 | Restore prev         | Restore new         |

### 3.2 Implementation Pattern (All Value Updates)

All block value updates follow the same pattern:

```elixir
def handle_event("update_block_value", %{"block_id" => id, "value" => value}, socket) do
  block = find_block(socket, id)
  prev_value = block.value

  case Sheets.update_block(block, %{value: value}) do
    {:ok, _updated} ->
      {:noreply,
       socket
       |> push_block_value_coalesced(id, prev_value, value)
       |> reload_blocks()}
    {:error, _} ->
      {:noreply, socket}
  end
end
```

### 3.3 Coalescing for Block Values

Block value edits (especially text typing) should coalesce:

```elixir
defp push_block_value_coalesced(socket, block_id, prev, new) do
  UndoRedoStack.push_coalesced(
    socket,
    {:update_block_value, block_id, prev, new},
    fn
      {:update_block_value, ^block_id, _, _} -> true
      _ -> false
    end,
    fn {:update_block_value, ^block_id, original_prev, _} ->
      {:update_block_value, block_id, original_prev, new}
    end
  )
end
```

### 3.4 Config Updates

Config changes are less frequent but more impactful (they change block behavior). No coalescing needed:

```elixir
def handle_event("save_block_config", params, socket) do
  block = socket.assigns.editing_block
  prev_config = block.config
  new_config = build_config(params)

  case Sheets.update_block(block, %{config: new_config}) do
    {:ok, _} ->
      {:noreply,
       socket
       |> UndoRedoStack.push_undo({:update_block_config, block.id, prev_config, new_config})
       |> reload_blocks()}
    {:error, _} ->
      {:noreply, socket}
  end
end
```

### 3.5 Undo/Redo Dispatch for Values & Config

```elixir
defp undo_action({:update_block_value, block_id, prev, _new}, socket) do
  block = Sheets.get_block!(block_id)
  case Sheets.update_block(block, %{value: prev}) do
    {:ok, _} -> {:ok, socket, {:update_block_value, block_id, prev, block.value}}
    {:error, _} -> {:error, socket}
  end
end

defp redo_action({:update_block_value, block_id, _prev, new}, socket) do
  block = Sheets.get_block!(block_id)
  case Sheets.update_block(block, %{value: new}) do
    {:ok, _} -> {:ok, socket, {:update_block_value, block_id, block.value, new}}
    {:error, _} -> {:error, socket}
  end
end

# Same pattern for config, constant toggle, rich text, boolean, reference, multi_select, select_options
```

---

## Phase 4 — Table Block Operations

Tables are the most complex entity in sheets. Each table block contains rows, columns, and cells. Undo/redo must handle operations at all three levels.

### 4.1 Action Types — Column Operations

| Action Tuple                                                                         | Trigger                                                         | Undo                            | Redo                         |
|--------------------------------------------------------------------------------------|-----------------------------------------------------------------|---------------------------------|------------------------------|
| `{:add_table_column, block_id, column_snapshot}`                                     | `add_table_column`                                              | Remove column + cells           | Re-add column + cells        |
| `{:delete_table_column, block_id, column_snapshot, cell_values}`                     | `delete_table_column`                                           | Restore column + cells          | Remove again                 |
| `{:rename_table_column, block_id, col_id, prev_name, new_name, prev_slug, new_slug}` | `rename_table_column`                                           | Restore prev name+slug+cells    | Restore new name+slug+cells  |
| `{:change_column_type, block_id, col_id, prev_type, new_type, prev_cells}`           | `change_table_column_type`                                      | Restore prev type + cell values | Apply new type + reset cells |
| `{:toggle_column_flag, block_id, col_id, flag, prev_value, new_value}`               | `toggle_table_column_constant` / `toggle_table_column_required` | Toggle back                     | Toggle forward               |
| `{:update_column_options, block_id, col_id, prev_options, new_options}`              | `add/update/remove_table_column_option`                         | Restore prev                    | Restore new                  |
| `{:update_number_constraint, block_id, col_id, field, prev_val, new_val}`            | `update_number_constraint`                                      | Restore prev                    | Restore new                  |

### 4.2 Action Types — Row Operations

| Action Tuple                                                 | Trigger              | Undo                | Redo               |
|--------------------------------------------------------------|----------------------|---------------------|--------------------|
| `{:add_table_row, block_id, row_snapshot}`                   | `add_table_row`      | Delete row + cells  | Re-add row + cells |
| `{:delete_table_row, block_id, row_snapshot, cell_values}`   | `delete_table_row`   | Restore row + cells | Remove again       |
| `{:rename_table_row, block_id, row_id, prev_name, new_name}` | `rename_table_row`   | Restore prev name   | Restore new name   |
| `{:reorder_table_rows, block_id, prev_order, new_order}`     | `reorder_table_rows` | Apply prev order    | Apply new order    |

### 4.3 Action Types — Cell Operations

| Action Tuple                                                               | Trigger                                                | Undo         | Redo        |
|----------------------------------------------------------------------------|--------------------------------------------------------|--------------|-------------|
| `{:update_table_cell, block_id, row_id, col_slug, prev_val, new_val}`      | `update_table_cell`                                    | Restore prev | Restore new |
| `{:toggle_table_cell_bool, block_id, row_id, col_slug, prev_val, new_val}` | `toggle_table_cell_boolean`                            | Restore prev | Restore new |
| `{:select_table_cell, block_id, row_id, col_slug, prev_val, new_val}`      | `select_table_cell` / `toggle_table_cell_multi_select` | Restore prev | Restore new |

### 4.4 Column Type Change — Complex Undo

Changing a column type resets ALL cell values to defaults. The undo must snapshot every cell value before the reset:

```elixir
def handle_event("change_table_column_type", %{"column_id" => col_id, "type" => new_type}, socket) do
  block = socket.assigns.block
  column = find_column(block, col_id)
  prev_type = column.type

  # Snapshot ALL cell values for this column across all rows
  prev_cells = snapshot_column_cells(block, column.slug)

  case Sheets.change_table_column_type(block, col_id, new_type) do
    {:ok, _} ->
      {:noreply,
       socket
       |> UndoRedoStack.push_undo(
         {:change_column_type, block.id, col_id, prev_type, new_type, prev_cells}
       )
       |> reload_blocks()}
    {:error, _} ->
      {:noreply, socket}
  end
end

defp snapshot_column_cells(block, column_slug) do
  Enum.map(block.table_rows, fn row ->
    {row.id, Map.get(row.cells || %{}, column_slug)}
  end)
end
```

**Undo of column type change:**

```elixir
defp undo_action({:change_column_type, block_id, col_id, prev_type, _new_type, prev_cells}, socket) do
  block = Sheets.get_block!(block_id)

  with {:ok, _} <- Sheets.change_table_column_type(block, col_id, prev_type),
       :ok <- Sheets.restore_column_cells(block_id, prev_cells) do
    {:ok, socket,
     {:change_column_type, block_id, col_id, prev_type,
      Sheets.get_column(block_id, col_id).type, snapshot_column_cells(block, col_id)}}
  else
    _ -> {:error, socket}
  end
end
```

### 4.5 Column Rename — Cell Key Migration

Renaming a column changes the slug, which means cell keys change too. The undo must reverse the key migration:

```elixir
defp undo_action({:rename_table_column, block_id, col_id, prev_name, _new_name, prev_slug, _new_slug}, socket) do
  block = Sheets.get_block!(block_id)
  case Sheets.rename_table_column(block, col_id, prev_name) do
    {:ok, _} ->
      {:ok, socket,
       {:rename_table_column, block_id, col_id, prev_name,
        Sheets.get_column(block_id, col_id).name,
        prev_slug, Sheets.get_column(block_id, col_id).slug}}
    {:error, _} -> {:error, socket}
  end
end
```

### 4.6 Cell Value Coalescing

Rapid cell edits (typing in a text cell) should coalesce, same as block values:

```elixir
defp push_cell_coalesced(socket, block_id, row_id, col_slug, prev, new) do
  UndoRedoStack.push_coalesced(
    socket,
    {:update_table_cell, block_id, row_id, col_slug, prev, new},
    fn
      {:update_table_cell, ^block_id, ^row_id, ^col_slug, _, _} -> true
      _ -> false
    end,
    fn {:update_table_cell, ^block_id, ^row_id, ^col_slug, original_prev, _} ->
      {:update_table_cell, block_id, row_id, col_slug, original_prev, new}
    end
  )
end
```

---

## Phase 5 — Compound & Complex Actions

### 5.1 Compound Action Pattern

Some operations affect multiple entities and must undo/redo as a single step. Use the Maps compound pattern:

```elixir
# Compound action = list of sub-actions
{:compound, [
  {:delete_table_column, block_id, column_snapshot, cell_values},
  {:update_block_config, block_id, prev_config, new_config}
]}
```

**Dispatch:**

```elixir
defp undo_action({:compound, actions}, socket) do
  Enum.reverse(actions)
  |> Enum.reduce_while({:ok, socket, []}, fn action, {:ok, socket, redo_items} ->
    case undo_action(action, socket) do
      {:ok, socket, redo_item} -> {:cont, {:ok, socket, [redo_item | redo_items]}}
      {:error, socket} -> {:halt, {:error, socket}}
    end
  end)
  |> case do
    {:ok, socket, redo_items} -> {:ok, socket, {:compound, Enum.reverse(redo_items)}}
    {:error, socket} -> {:error, socket}
  end
end

defp redo_action({:compound, actions}, socket) do
  Enum.reduce_while(actions, {:ok, socket, []}, fn action, {:ok, socket, undo_items} ->
    case redo_action(action, socket) do
      {:ok, socket, undo_item} -> {:cont, {:ok, socket, [undo_item | undo_items]}}
      {:error, socket} -> {:halt, {:error, socket}}
    end
  end)
  |> case do
    {:ok, socket, undo_items} -> {:ok, socket, {:compound, Enum.reverse(undo_items)}}
    {:error, socket} -> {:error, socket}
  end
end
```

### 5.2 Operations That Need Compound Actions

| Operation                                     | Sub-Actions                                                           |
|-----------------------------------------------|-----------------------------------------------------------------------|
| Add column (creates cells for all rows)       | `{:add_table_column, ...}` (column + cells are atomic in the context) |
| Delete column (removes cells from all rows)   | `{:delete_table_column, ...}` (includes cell snapshot)                |
| Column type change (resets all cells)         | Single action with cell snapshot (not compound)                       |
| Create column group (affects multiple blocks) | `{:compound, [{:create_column_group, ...}, {:reorder_blocks, ...}]}`  |

**Note:** Most table operations are inherently atomic at the context layer (e.g., `delete_table_column` already removes cells). Compound actions are mainly needed when an operation triggers side-effects in unrelated entities.

### 5.3 Inheritance Operations (Deferred)

Block inheritance operations (`detach_block`, `reattach_block`, `hide_for_children`, `unhide_for_children`) affect multiple sheets (parent + children). These are **deferred** from the initial implementation because:

1. They cross sheet boundaries (undo stack is per-sheet)
2. They have cascading effects on child sheets
3. They're infrequent operations
4. Getting them wrong could corrupt the inheritance tree

**Future approach:** Track inheritance changes as compound actions that include both the local change and a list of affected child sheets. Undo would need to cascade to children as well.

---

## Phase 6 — Keyboard Shortcut Unification

### 6.1 Current State

| Editor   | Hook         | Location                     | Approach                         |
|----------|--------------|------------------------------|----------------------------------|
| Maps     | `MapCanvas`  | `map_canvas.js:308-321`      | Embedded in hook keydown handler |
| Flows    | `FlowCanvas` | `keyboard_handler.js:91-105` | Separate handler module          |
| Sheets   | None         | —                            | Not implemented                  |

### 6.2 Plan

- **Sheets:** Use the new `UndoRedo` hook (Phase 0.3) attached to the sheet editor container
- **Maps:** Keep existing (embedded in `MapCanvas` hook — refactoring would be risky for no benefit)
- **Flows:** Keep existing (deeply integrated with Rete.js history plugin)

### 6.3 Sheet LiveView Integration

```heex
<%!-- In sheet_live/show.html.heex or content_tab.ex ---%>
<div id="sheet-editor" phx-hook="UndoRedo">
  <%!-- Sheet editor content --%>
</div>
```

The hook pushes `"undo"` / `"redo"` events to the LiveView, which delegates to `UndoRedoHandlers`:

```elixir
# In show.ex
def handle_event("undo", params, socket) do
  UndoRedoHandlers.handle_undo(params, socket)
end

def handle_event("redo", params, socket) do
  UndoRedoHandlers.handle_redo(params, socket)
end
```

---

## Files Modified Summary

### New Files

| File                                                              | Purpose                         |
|-------------------------------------------------------------------|---------------------------------|
| `lib/storyarn_web/helpers/undo_redo_stack.ex`                     | Shared stack management module  |
| `lib/storyarn_web/live/sheet_live/handlers/undo_redo_handlers.ex` | Sheet undo/redo action dispatch |
| `assets/js/hooks/undo_redo.js`                                    | Generic keyboard shortcut hook  |
| `test/storyarn_web/live/sheet_live/undo_redo_test.exs`            | Sheet undo/redo tests           |
| `test/storyarn_web/helpers/undo_redo_stack_test.exs`              | Shared module tests             |

### Modified Files

| File                                                               | Changes                                  |
|--------------------------------------------------------------------|------------------------------------------|
| `lib/storyarn_web/live/map_live/handlers/undo_redo_handlers.ex`    | Delegate stack ops to shared module      |
| `lib/storyarn_web/live/map_live/handlers/element_handlers.ex`      | Update imports for shared module         |
| `lib/storyarn_web/live/map_live/handlers/layer_handlers.ex`        | Update imports for shared module         |
| `lib/storyarn_web/live/sheet_live/show.ex`                         | Add undo/redo event handlers, init stack |
| `lib/storyarn_web/live/sheet_live/handlers/block_crud_handlers.ex` | Add undo recording to all operations     |
| `lib/storyarn_web/live/sheet_live/handlers/table_handlers.ex`      | Add undo recording to all operations     |
| `lib/storyarn_web/live/sheet_live/handlers/config_helpers.ex`      | Add undo recording to config changes     |
| `lib/storyarn_web/live/sheet_live/components/content_tab.ex`       | Add UndoRedo hook to template            |
| `lib/storyarn/sheets.ex`                                           | Add `create_block_from_snapshot/2`       |
| `assets/js/app.js`                                                 | Register `UndoRedo` hook                 |

### Untouched Files (Explicitly)

| File                                                 | Reason                                              |
|------------------------------------------------------|-----------------------------------------------------|
| `assets/js/flow_canvas/history_preset.js`            | Flows use client-side undo — different architecture |
| `assets/js/flow_canvas/handlers/keyboard_handler.js` | Flows keyboard shortcuts are Rete-integrated        |
| `assets/js/hooks/map_canvas.js`                      | Maps keyboard shortcuts work fine as-is             |
| `lib/storyarn_web/live/flow_live/*`                  | Flows undo/redo is independent                      |

---

## Testing Strategy

### Unit Tests — Shared Module

```elixir
# test/storyarn_web/helpers/undo_redo_stack_test.exs
describe "push_undo/2" do
  test "adds action to undo stack and clears redo"
  test "caps at max size"
end

describe "push_coalesced/4" do
  test "merges when top matches"
  test "pushes new when top doesn't match"
  test "pushes new on empty stack"
end

describe "pop_undo/1" do
  test "returns action and updated socket"
  test "returns :empty on empty stack"
end
```

### Integration Tests — Sheet Undo/Redo

```elixir
# test/storyarn_web/live/sheet_live/undo_redo_test.exs
describe "sheet metadata" do
  test "undo/redo sheet name change"
  test "undo/redo sheet color change"
  test "name changes coalesce into single undo entry"
end

describe "block CRUD" do
  test "undo block creation deletes the block"
  test "redo block creation restores the block with same ID"
  test "undo block deletion recreates with all attributes"
  test "undo/redo block reorder"
end

describe "block values" do
  test "undo/redo text value change"
  test "undo/redo boolean toggle"
  test "undo/redo select value"
  test "rapid value edits coalesce"
end

describe "table columns" do
  test "undo column creation removes column and cells"
  test "undo column deletion restores column and all cell values"
  test "undo column type change restores old type and cell values"
  test "undo column rename restores name, slug, and cell keys"
end

describe "table rows" do
  test "undo row creation removes row and cells"
  test "undo row deletion restores row and all cell values"
  test "undo row reorder restores previous order"
end

describe "table cells" do
  test "undo/redo cell value change"
  test "undo/redo boolean cell toggle"
  test "undo/redo multi-select toggle"
  test "rapid cell edits coalesce"
end

describe "compound actions" do
  test "undo compound reverses sub-actions in order"
  test "redo compound applies sub-actions in order"
end

describe "stack behavior" do
  test "new action clears redo stack"
  test "undo pushes to redo stack"
  test "redo pushes to undo without clearing redo"
  test "empty stack undo is no-op"
  test "empty stack redo is no-op"
  test "stack caps at 50 entries"
end
```

### Regression Tests — Maps

After refactoring Maps to use the shared module, run the existing test suite:

```bash
mix test test/storyarn_web/live/map_live/undo_redo_test.exs
```

All 25+ existing tests must pass unchanged.

---

## Implementation Order

| Step  | Phase  | Description                                            | Complexity  | Depends On  |
|-------|--------|--------------------------------------------------------|-------------|-------------|
| 1     | 0.1    | Create `UndoRedoStack` shared module + tests           | Low         | —           |
| 2     | 0.2    | Refactor Maps to use shared module + verify tests pass | Low         | Step 1      |
| 3     | 0.3    | Create `UndoRedo` JS hook + register in app.js         | Low         | —           |
| 4     | 1      | Sheet metadata undo/redo (name, color, etc.)           | Low-Medium  | Steps 1, 3  |
| 5     | 2      | Block CRUD undo/redo (create, delete, reorder)         | Medium      | Step 4      |
| 6     | 3      | Block value & config undo/redo + coalescing            | Medium      | Step 5      |
| 7     | 4      | Table operations undo/redo (columns, rows, cells)      | High        | Step 6      |
| 8     | 5      | Compound actions for multi-entity operations           | Medium      | Step 7      |

**Steps 1 and 3 can be done in parallel.** Steps 4-8 are sequential.

**Estimated effort:** Steps 1-3 are small. Steps 4-6 are medium. Steps 7-8 are the bulk of the work due to table operation complexity.

---

## Future Considerations

### Collaboration Handling (Deferred)

Currently none of the editors handle undo/redo conflicts during collaboration:
- **Maps:** No per-user awareness
- **Flows:** `data.self` flag + node locking prevents most conflicts
- **Sheets:** No collaboration-aware undo

For v2, consider:
- Per-user undo stacks (already natural — socket assigns are per-connection)
- Operational Transform (OT) for concurrent text edits
- Conflict detection: if the element was modified by another user since the action was recorded, skip the undo and notify

### Undo History Persistence (Deferred)

Currently all undo history is session-only (lost on page refresh). For v2:
- Could persist undo stacks to Redis with session key
- Recovery on reconnect
- Cross-tab undo (unlikely to be needed)

### Inheritance Operations (Deferred)

Block inheritance (`detach`, `reattach`, `hide_for_children`) crosses sheet boundaries. Requires:
- Cross-sheet undo coordination
- Careful cascade handling
- Significant additional complexity

### Undo UI Button (Optional)

All editors currently use keyboard-only undo. Consider adding toolbar buttons:
- Undo/redo buttons with disabled state based on `can_undo?/can_redo?`
- Tooltip showing the action that will be undone (e.g., "Undo: delete block")
- History dropdown showing recent actions

---

## Appendix A: Complete Action Type Registry

### Maps (Existing — 15 action types)

```
{:create_pin, pin}
{:delete_pin, pin}
{:move_pin, pin_id, prev, new}
{:update_pin, pin_id, prev_attrs, new_attrs}
{:create_zone, zone}
{:delete_zone, zone}
{:update_zone, zone_id, prev_attrs, new_attrs}
{:update_zone_vertices, zone_id, prev_vertices, new_vertices}
{:create_connection, conn}
{:delete_connection, conn}
{:update_connection, conn_id, prev_attrs, new_attrs}
{:update_connection_waypoints, conn_id, prev_waypoints, new_waypoints}
{:create_annotation, annotation}
{:delete_annotation, annotation}
{:move_annotation, ann_id, prev, new}
{:update_annotation, ann_id, prev_attrs, new_attrs}
{:create_layer, layer}
{:delete_layer, layer}
{:rename_layer, layer_id, prev_name, new_name}
{:update_layer_fog, layer_id, prev_attrs, new_attrs}
{:compound, [sub_actions]}
```

### Flows (Existing — 8 action classes)

```
DragAction(nodeId, prevPos, newPos)
AddConnectionAction(connectionData)
RemoveConnectionAction(connectionData)
DeleteNodeAction(nodeId, nodeData)
CreateNodeAction(nodeId)
FlowMetaAction(field, prevValue, newValue)
NodeDataAction(nodeId, prevData, newData)
AutoLayoutAction(prevPositions, newPositions)
```

### Sheets (Proposed — 25+ action types)

```
# Metadata (6)
{:update_sheet_name, prev, new}
{:update_sheet_shortcut, prev, new}
{:update_sheet_color, prev, new}
{:update_sheet_description, prev, new}
{:update_sheet_avatar, prev_asset_id, new_asset_id}
{:update_sheet_banner, prev_asset_id, new_asset_id}

# Block CRUD (5)
{:create_block, block_snapshot}
{:delete_block, block_snapshot}
{:reorder_blocks, prev_order, new_order}
{:reorder_with_columns, prev_items, new_items}
{:create_column_group, block_ids, group_id}

# Block values & config (10)
{:update_block_value, block_id, prev, new}
{:update_block_config, block_id, prev_config, new_config}
{:toggle_constant, block_id, prev, new}
{:update_rich_text, block_id, prev, new}
{:set_boolean_block, block_id, prev, new}
{:select_reference, block_id, prev_ref, new_ref}
{:toggle_multi_select, block_id, prev, new}
{:add_select_option, block_id, prev_options, new_options}
{:remove_select_option, block_id, prev_options, new_options}
{:update_select_option, block_id, prev_options, new_options}

# Table columns (7)
{:add_table_column, block_id, column_snapshot}
{:delete_table_column, block_id, column_snapshot, cell_values}
{:rename_table_column, block_id, col_id, prev_name, new_name, prev_slug, new_slug}
{:change_column_type, block_id, col_id, prev_type, new_type, prev_cells}
{:toggle_column_flag, block_id, col_id, flag, prev, new}
{:update_column_options, block_id, col_id, prev_options, new_options}
{:update_number_constraint, block_id, col_id, field, prev, new}

# Table rows (4)
{:add_table_row, block_id, row_snapshot}
{:delete_table_row, block_id, row_snapshot, cell_values}
{:rename_table_row, block_id, row_id, prev_name, new_name}
{:reorder_table_rows, block_id, prev_order, new_order}

# Table cells (3)
{:update_table_cell, block_id, row_id, col_slug, prev, new}
{:toggle_table_cell_bool, block_id, row_id, col_slug, prev, new}
{:select_table_cell, block_id, row_id, col_slug, prev, new}

# Compound
{:compound, [sub_actions]}
```

---

## Appendix B: Comparison of Architectures

| Aspect         | Maps (Server)                    | Flows (Client)                 | Sheets (Proposed Server)        |
|----------------|----------------------------------|--------------------------------|---------------------------------|
| Stack location | Socket assigns                   | JS HistoryPlugin               | Socket assigns                  |
| Stack cap      | 50                               | Unbounded                      | 50                              |
| Persistence    | Session-only                     | Session-only                   | Session-only                    |
| Action format  | Elixir tuples                    | JS classes                     | Elixir tuples                   |
| Coalescing     | `push_undo_coalesced/2`          | Timestamp-based                | `push_coalesced/4`              |
| Compound       | `{:compound, [...]}`             | N/A                            | `{:compound, [...]}`            |
| ID handling    | Hard-delete + new IDs + rebasing | Soft-delete + preserved IDs    | Hard-delete + UUID preservation |
| Keyboard hook  | Embedded in `MapCanvas`          | Embedded in `keyboard_handler` | Standalone `UndoRedo` hook      |
| Collaboration  | None                             | `self` flag + locking          | None (v1)                       |
| Test coverage  | 750+ lines                       | Minimal                        | Target: 500+ lines              |
| Shared module  | After refactor: `UndoRedoStack`  | Independent                    | `UndoRedoStack`                 |
