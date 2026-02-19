# Maps — Undo/Redo Enhancement Plan

> **Goal:** Extend the existing server-side undo/redo stack from delete-only to all mutating operations
>
> **Priority:** High — move and vertex editing are the most destructive gaps (geometry lost with no recovery)
>
> **Last Updated:** February 19, 2026

## Current State

Maps use a **server-side** undo/redo system stored in socket assigns (`undo_stack`, `redo_stack` — lists of tagged tuples, capped at 50). Keyboard shortcuts `Ctrl+Z`/`Ctrl+Y` fire `pushEvent("undo")`/`pushEvent("redo")` from `map_canvas.js`, handled by `UndoRedoHandlers`.

Currently only **delete** operations are tracked:

| Action Tuple | Undo | Redo |
|---|---|---|
| `{:delete_pin, pin}` | `Maps.create_pin()` (new ID) | `Maps.delete_pin()` |
| `{:delete_zone, zone}` | `Maps.create_zone()` (new ID) | `Maps.delete_zone()` |
| `{:delete_connection, conn}` | `Maps.create_connection()` (new ID) | `Maps.delete_connection()` |
| `{:delete_annotation, ann}` | `Maps.create_annotation()` (new ID) | `Maps.delete_annotation()` |

### Key Design Constraints

- **ID rebasing** — undo re-creates elements with new DB IDs. The redo action stores the recreated struct to find it later by the new ID. Subsequent undo operations on the same element must account for the ID change.
- **`push_undo/2`** clears the redo stack (standard behavior). **`push_undo_no_clear/2`** is used internally by redo to re-push without clearing.
- **No collaboration awareness** — undo affects all users' view. No `self` flag distinction.
- **Stack cap:** 50 entries per direction.

---

## Phase 1 — Move Operations

The most impactful gap. Moving a pin or annotation loses the original position permanently.

### 1.1 Pin Move

**Action tuple:** `{:move_pin, pin_id, prev_position, new_position}`

```elixir
# prev_position = %{x: float, y: float}
# new_position = %{x: float, y: float}
```

**Recording point:** In `do_move_pin/3` (`element_handlers.ex`), capture before/after:

```elixir
defp do_move_pin(socket, pin, %{"x" => x, "y" => y}) do
  prev = %{x: pin.position_x, y: pin.position_y}

  case Maps.update_pin(pin, %{position_x: x, position_y: y}) do
    {:ok, _updated} ->
      new = %{x: x, y: y}

      socket
      |> push_undo({:move_pin, pin.id, prev, new})
      |> reload_map()

    {:error, _} ->
      socket
  end
end
```

**Undo/redo handlers** in `undo_redo_handlers.ex`:

```elixir
defp undo_action({:move_pin, pin_id, prev_position, _new_position}, socket) do
  pin = find_pin(socket, pin_id)

  if pin do
    case Maps.update_pin(pin, %{position_x: prev_position.x, position_y: prev_position.y}) do
      {:ok, _} -> {:ok, socket, {pin_id, prev_position}}
      {:error, _} -> {:error, socket}
    end
  else
    {:error, socket}
  end
end

defp redo_action({:move_pin, pin_id, _prev_position, new_position}, socket) do
  pin = find_pin(socket, pin_id)

  if pin do
    case Maps.update_pin(pin, %{position_x: new_position.x, position_y: new_position.y}) do
      {:ok, _} -> {:ok, socket}
      {:error, _} -> {:error, socket}
    end
  else
    {:error, socket}
  end
end
```

**Note:** Unlike delete actions, move actions don't change IDs. The same `pin_id` is valid across undo/redo.

### 1.2 Annotation Move

Same pattern as pin move:

**Action tuple:** `{:move_annotation, annotation_id, prev_position, new_position}`

**Recording point:** In `do_move_annotation/3`.

### 1.3 Move Coalescing

Drag operations fire `move_pin` events rapidly (debounced on the client, but still multiple per drag). Each push to the undo stack clears the redo stack, which is correct, but we want to coalesce moves of the same element within a short window.

**Strategy:** Check if the top of the undo stack is a move for the same element. If so, update the `new_position` in place instead of pushing a new entry:

```elixir
defp push_undo_coalesced(socket, {:move_pin, pin_id, prev, new}) do
  case socket.assigns.undo_stack do
    [{:move_pin, ^pin_id, original_prev, _old_new} | rest] ->
      updated = {:move_pin, pin_id, original_prev, new}
      assign(socket, undo_stack: [updated | rest], redo_stack: [])

    _ ->
      push_undo(socket, {:move_pin, pin_id, prev, new})
  end
end
```

Same for `{:move_annotation, ...}`.

---

## Phase 2 — Create Operations (Symmetric with Delete)

Currently delete is undoable but create is not. This is asymmetric and confusing.

### 2.1 Pin Create

**Action tuple:** `{:create_pin, pin_id}`

**Recording point:** After successful `Maps.create_pin()` in `handle_create_pin`:

```elixir
socket
|> push_undo({:create_pin, pin.id})
|> reload_map()
```

**Undo:** Delete the pin. **Redo:** Restore it.

**Problem: ID rebasing.** When undo deletes the pin and redo needs to restore it, the pin no longer exists with that ID. Two options:

**Option A — Soft-delete for maps** (like flows):

Add `deleted_at` to pins/zones/connections/annotations. Undo of create soft-deletes; redo clears `deleted_at`. IDs are preserved.

**Option B — Store full struct for recreation:**

```elixir
# Action becomes: {:create_pin, pin_struct}
# Undo: Maps.delete_pin(pin) → push_redo({:create_pin, pin_struct_with_attrs})
# Redo: Maps.create_pin(map, attrs_from_struct) → new ID, update action
```

This is what the current delete undo already does (stores full struct, re-creates on undo with new ID).

**Recommended: Option B** — it's consistent with the existing delete pattern and doesn't require schema changes. Accept ID instability.

### 2.2 Zone Create

Same pattern: `{:create_zone, zone_struct}`

### 2.3 Connection Create

Same pattern: `{:create_connection, connection_struct}`

### 2.4 Annotation Create

Same pattern: `{:create_annotation, annotation_struct}`

### 2.5 Duplicate & Paste

Duplicate and paste both create new elements. They should push the same `{:create_*, struct}` action. No special handling needed.

---

## Phase 3 — Property Edits (Snapshot-Based)

### 3.1 Architecture: `{:update_*, id, prev_attrs, new_attrs}`

Store only the changed attributes, not the full struct:

```elixir
{:update_pin, pin_id, %{label: "Old"}, %{label: "New"}}
{:update_zone, zone_id, %{name: "Old", fill_color: "#fff"}, %{name: "New", fill_color: "#000"}}
{:update_connection, conn_id, %{label: "Old"}, %{label: "New"}}
{:update_annotation, annotation_id, %{text: "Old"}, %{text: "New"}}
```

### 3.2 Helper: Capture Changed Attrs

```elixir
defp capture_changes(element, new_attrs) do
  prev_attrs =
    new_attrs
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, acc ->
      Map.put(acc, key, Map.get(element, key))
    end)

  {prev_attrs, new_attrs}
end
```

### 3.3 Pin Property Update

**Recording point:** In `do_update_pin/3`:

```elixir
defp do_update_pin(socket, pin, attrs) do
  {prev, new} = capture_changes(pin, attrs)

  case Maps.update_pin(pin, attrs) do
    {:ok, _updated} ->
      socket
      |> push_undo({:update_pin, pin.id, prev, new})
      |> reload_map()

    {:error, _} ->
      socket
  end
end
```

**Undo/redo:**

```elixir
defp undo_action({:update_pin, pin_id, prev_attrs, _new_attrs}, socket) do
  pin = find_pin(socket, pin_id)
  if pin do
    case Maps.update_pin(pin, prev_attrs) do
      {:ok, _} -> {:ok, socket, {pin_id, prev_attrs}}
      {:error, _} -> {:error, socket}
    end
  else
    {:error, socket}
  end
end
```

### 3.4 Zone Property Update

Same pattern with `{:update_zone, zone_id, prev, new}`.

### 3.5 Zone Vertices Update (Reshape)

Special case — vertices are a list of `%{x, y}` maps, and reshaping changes the entire geometry.

**Action tuple:** `{:update_zone_vertices, zone_id, prev_vertices, new_vertices}`

**Recording point:** In `do_update_zone_vertices/3`:

```elixir
defp do_update_zone_vertices(socket, zone, vertices) do
  prev_vertices = zone.vertices  # [{x, y}, ...]

  case Maps.update_zone(zone, %{vertices: vertices}) do
    {:ok, _updated} ->
      socket
      |> push_undo({:update_zone_vertices, zone.id, prev_vertices, vertices})
      |> reload_map()

    {:error, _} ->
      socket
  end
end
```

### 3.6 Connection Property Update

Same pattern: `{:update_connection, conn_id, prev, new}`.

### 3.7 Connection Waypoints Update

**Action tuple:** `{:update_waypoints, conn_id, prev_waypoints, new_waypoints}`

Includes `clear_waypoints` — prev = current waypoints, new = `[]`.

### 3.8 Annotation Property Update

Same pattern: `{:update_annotation, annotation_id, prev, new}`.

---

## Phase 4 — Layer Operations

### 4.1 Layer Create

**Action tuple:** `{:create_layer, layer_id}`

Undo: delete the layer (move elements to no-layer first). Redo: re-create with same attributes.

### 4.2 Layer Delete

**Action tuple:** `{:delete_layer, layer_struct, affected_elements}`

The `affected_elements` list stores which pins/zones/annotations were on this layer, so undo can reassign them.

### 4.3 Layer Rename

**Action tuple:** `{:rename_layer, layer_id, prev_name, new_name}`

### 4.4 Layer Fog Update

**Action tuple:** `{:update_layer_fog, layer_id, prev_fog, new_fog}`

---

## Phase 5 — Compound Actions

Some operations involve multiple elements. These need to be grouped so a single Ctrl+Z undoes the entire batch.

### 5.1 Compound Action Wrapper

```elixir
# A compound action is a list of sub-actions:
{:compound, [
  {:delete_pin, pin1},
  {:delete_pin, pin2},
  {:delete_connection, conn1}
]}
```

**Undo:** Execute all sub-action undos in reverse order. **Redo:** Execute all in forward order.

```elixir
defp undo_action({:compound, actions}, socket) do
  Enum.reduce(Enum.reverse(actions), {:ok, socket, []}, fn
    action, {:ok, socket, recreated} ->
      case undo_action(action, socket) do
        {:ok, socket, item} -> {:ok, socket, [item | recreated]}
        {:error, socket} -> {:error, socket}
      end

    _action, {:error, socket} ->
      {:error, socket}
  end)
end
```

### 5.2 Use Cases for Compound Actions

- **Multi-select delete:** Delete multiple pins/zones at once → single undo restores all
- **Delete pin with connections:** Deleting a pin also removes its connections → compound groups them
- **Delete layer with reassignment:** Layer delete + element reassignment

---

## Refactoring: `undo_action` / `redo_action` Dispatch

The current code pattern-matches each action tuple. With the new actions, this grows large. Refactor into a clean dispatch:

```elixir
# undo_redo_handlers.ex

defp undo_action({:compound, actions}, socket), do: ...

defp undo_action({:delete_pin, pin}, socket), do: recreate_element(:pin, pin, socket)
defp undo_action({:delete_zone, zone}, socket), do: recreate_element(:zone, zone, socket)
# ... etc

defp undo_action({:create_pin, pin}, socket), do: delete_element(:pin, pin, socket)
# ... etc

defp undo_action({:move_pin, id, prev, _new}, socket), do: update_position(:pin, id, prev, socket)
defp undo_action({:move_annotation, id, prev, _new}, socket), do: update_position(:annotation, id, prev, socket)

defp undo_action({:update_pin, id, prev, _new}, socket), do: update_attrs(:pin, id, prev, socket)
# ... etc
```

Group by operation type with shared private helpers to keep the code DRY.

---

## Summary

| Phase | Operations | Complexity |
|-------|-----------|------------|
| 1 | Pin move, annotation move (with coalescing) | Low |
| 2 | Create pin/zone/connection/annotation, duplicate, paste | Medium |
| 3 | Property edits for all element types, vertex reshape, waypoints | Medium |
| 4 | Layer create/delete/rename/fog | Medium |
| 5 | Compound actions (multi-select delete, cascading deletes) | Medium-High |

### Files Modified

| File | Changes |
|------|---------|
| `lib/storyarn_web/live/map_live/handlers/undo_redo_handlers.ex` | Add all new action handlers, compound dispatch, helper functions |
| `lib/storyarn_web/live/map_live/handlers/element_handlers.ex` | Add `push_undo` calls to move, create, update, duplicate, paste operations |
| `lib/storyarn_web/live/map_live/handlers/zone_handlers.ex` | Add `push_undo` calls to zone update, vertex update |
| `lib/storyarn_web/live/map_live/handlers/connection_handlers.ex` | Add `push_undo` calls to connection update, waypoint update |
| `lib/storyarn_web/live/map_live/handlers/annotation_handlers.ex` | Add `push_undo` calls to annotation move, update |
| `lib/storyarn_web/live/map_live/handlers/layer_handlers.ex` | Add `push_undo` calls to layer create/delete/rename/fog |

### Verification

```bash
mix compile --warnings-as-errors
mix test

# Manual testing per phase:
# Phase 1: Move pin → Ctrl+Z should return to original position → Ctrl+Y re-moves
# Phase 1: Drag rapidly → should coalesce into single undo step
# Phase 2: Create pin → Ctrl+Z should delete it → Ctrl+Y re-creates
# Phase 3: Edit pin label → Ctrl+Z reverts → Ctrl+Y re-applies
# Phase 3: Reshape zone → Ctrl+Z restores original vertices
# Phase 4: Create layer → Ctrl+Z deletes it
# Phase 5: Multi-select delete → single Ctrl+Z restores all elements
```
