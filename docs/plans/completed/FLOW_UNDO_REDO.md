# Flow Editor — Undo/Redo Enhancement Plan

> **Goal:** Extend the existing client-side history system to cover all mutating operations, not just drag/connection/delete
>
> **Priority:** High — property edits are the most frequent user action and have zero undo coverage
>
> **Last Updated:** February 19, 2026

## Current State

The flow editor uses `rete-history-plugin` with a custom preset (`history_preset.js`). History lives client-side in JavaScript. Four action classes exist:

| Action                   | Undo                                                     | Redo                                            |
|--------------------------|----------------------------------------------------------|-------------------------------------------------|
| `DragAction`             | `area.translate()` to previous position                  | `area.translate()` to new position              |
| `AddConnectionAction`    | `editor.removeConnection()`                              | `editor.addConnection()`                        |
| `RemoveConnectionAction` | `editor.addConnection()`                                 | `editor.removeConnection()`                     |
| `DeleteNodeAction`       | `pushEvent("restore_node")` — server soft-delete restore | `pushEvent("delete_node")` — server soft-delete |

Everything else (node creation, duplication, all property edits) goes straight to the DB with no undo.

### Key Design Constraints

- **Client-side history stack** — the `HistoryPlugin` is JS-only; undo/redo don't hit the server unless the action class explicitly calls `pushEvent`
- **`isLoadingFromServer` guard** — counter-based flag that prevents server-pushed changes (collaborator updates, initial load) from entering the history stack
- **`_historyTriggeredDelete` flag** — prevents redo of deletion from double-recording into history
- **Collaboration** — `data.self` flag ensures only the initiating user records actions; collaborators see the effect but don't get it in their own stack
- **Soft-delete** — node IDs are preserved across undo/redo cycles (unlike Scenes which re-create with new IDs)
- **Orphaned cascades** — deleting a hub that cascades orphaned jumps triggers `flow_updated` which calls `history.clear()`, wiping all prior history

---

## Phase 1 — Node Creation & Duplication

Symmetric undo for the operations that currently have no inverse.

### 1.1 `CreateNodeAction`

When a node is created (`node_added` event with `self: true`), push a `CreateNodeAction`.

```js
class CreateNodeAction {
  constructor(hook, nodeId) {
    this.hook = hook;
    this.nodeId = nodeId;
  }

  async undo() {
    // Re-use existing delete path (soft-delete)
    this.hook._historyTriggeredDelete = this.nodeId;
    this.hook.pushEvent("delete_node", { id: this.nodeId });
  }

  async redo() {
    // Re-use existing restore path
    this.hook.pushEvent("restore_node", { id: this.nodeId });
  }
}
```

**Recording point:** In `handleNodeAdded` (editor_handlers.js), after the node is added to the editor, if `data.self && !hook.isLoadingFromServer`:

```js
if (data.self && !hook.isLoadingFromServer) {
  hook.history?.add(new CreateNodeAction(hook, data.id));
}
```

**Server changes:** None — `delete_node` and `restore_node` already exist.

**`data.self` flag:** `add_node/2` in `node_helpers.ex` needs to include `self: true` in the `node_added` push_event payload (currently not present). Add it.

### 1.2 `DuplicateNodeAction`

Identical to `CreateNodeAction` — duplicate creates a new node, undo deletes it, redo restores it.

```js
class DuplicateNodeAction extends CreateNodeAction {}
```

**Recording point:** In `handleNodeAdded`, use a flag `_duplicateTriggered` set before `pushEvent("duplicate_node")` to distinguish duplicates from plain creates, if different behavior is needed in the future. For now, same action class.

### 1.3 Guard: Prevent Delete-Undo of Created Node from Double-Recording

When `CreateNodeAction.undo()` fires, it calls `pushEvent("delete_node")`. The server responds with `node_removed` → `handleNodeRemoved`. The existing `_historyTriggeredDelete` flag already prevents double-recording. No new logic needed.

### 1.4 Guard: Prevent Restore from Recording as Create

When `DeleteNodeAction.undo()` fires `restore_node`, the server responds with `node_restored`. The existing `enterLoadingFromServer()` call in `handleNodeRestored` already prevents recording. No new logic needed.

---

## Phase 2 — Node Property Edits (Snapshot-Based)

Property edits are the hardest category because they go through `persist_node_update/3` on the server and the data is a free-form map. We need a **snapshot-before-edit** strategy.

### 2.1 Architecture: `NodeDataAction`

```js
class NodeDataAction {
  constructor(hook, nodeId, prevData, newData) {
    this.hook = hook;
    this.nodeId = nodeId;
    this.prevData = prevData;   // full node.data snapshot before edit
    this.newData = newData;     // full node.data snapshot after edit
  }

  async undo() {
    this.hook.pushEvent("restore_node_data", {
      id: this.nodeId,
      data: this.prevData
    });
  }

  async redo() {
    this.hook.pushEvent("restore_node_data", {
      id: this.nodeId,
      data: this.newData
    });
  }
}
```

### 2.2 Server: `restore_node_data` event

New handler in `generic_node_handlers.ex`:

```elixir
def handle_event("restore_node_data", %{"id" => node_id, "data" => data}, socket) do
  with_auth(socket, :edit_content, fn ->
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    case Flows.update_node_data(node, data) do
      {:ok, updated_node, _meta} ->
        socket
        |> maybe_update_selected(updated_node)
        |> push_event("node_updated", canvas_payload(updated_node))
      {:error, _} ->
        put_flash(socket, :error, "...")
    end
  end)
end
```

This replaces the entire `data` map. Since `persist_node_update` already calls `Flows.update_node_data(node, new_data)`, the restore path is the same code.

### 2.3 Capturing Snapshots: `data-before-edit` Pattern

The client needs the **before** snapshot to record a `NodeDataAction`. Two strategies:

**Option A — Server pushes `prev_data` in response:**

When `persist_node_update` runs, it already reads the fresh node (`Flows.get_node!`). Capture `old_data = node.data` before applying `update_fn`, and include it in the response event:

```elixir
# In persist_node_update:
node = Flows.get_node!(flow.id, node_id)
old_data = node.data
new_data = update_fn.(old_data)
# ... after success:
push_event(socket, "node_data_changed", %{
  id: node_id,
  prev_data: old_data,
  new_data: new_data
})
```

The client handler records:

```js
handleEvent("node_data_changed", ({ id, prev_data, new_data }) => {
  if (!hook.isLoadingFromServer) {
    hook.history?.add(new NodeDataAction(hook, id, prev_data, new_data));
  }
});
```

**Option B — Client caches `selectedNode.data` before each edit:**

Store `hook._nodeDataSnapshot[nodeId]` when the sidebar opens or on first keydown. Compare after server ack. This avoids server changes but is fragile.

**Recommended: Option A** — the server is the source of truth and already has both before/after.

### 2.4 Coalescing Rapid Edits

Text typing generates many `update_node_text` events (debounced at ~300ms). Each would create a separate `NodeDataAction`. We need coalescing similar to `DragAction`:

```js
// In the event handler for node_data_changed:
const recent = hook.history?.getRecent(timing);
const existing = recent?.find(
  a => a instanceof NodeDataAction && a.nodeId === id
);

if (existing) {
  // Update the newData endpoint, keep original prevData
  existing.newData = new_data;
  existing.timestamp = Date.now();
} else {
  hook.history?.add(new NodeDataAction(hook, id, prev_data, new_data));
}
```

**Timing window:** 1000ms (longer than drag's 400ms, since text editing has longer pauses between meaningful changes).

### 2.5 Operations Covered

All of these go through `persist_node_update` and would automatically get undo/redo:

- Dialogue: text, speaker, stage directions, menu text, technical ID, localization ID, audio asset
- Dialogue responses: add, remove, text change, condition change, instruction change
- Condition: expression, builder, switch mode toggle
- Instruction: builder update
- Hub: label, hub_id, color
- Jump: target hub
- Exit: mode, reference, outcome tags
- Entry: label

### 2.6 Edge Case: `flow_updated` After Rename Cascades

When `persist_node_update` triggers a `flow_updated` (e.g., renaming a hub_id causes jump label changes), the full flow refresh calls `history.clear()`. This is a known limitation. Two approaches:

- **Accept it:** Hub ID renames are rare. Document the limitation.
- **Targeted fix:** Instead of `flow_updated`, push individual `node_updated` events for each affected node. This is a larger refactor.

**Recommended:** Accept for Phase 2, fix in Phase 4.

---

## Phase 3 — Flow Metadata

### 3.1 `FlowMetaAction`

For flow name and shortcut changes:

```js
class FlowMetaAction {
  constructor(hook, field, prevValue, newValue) {
    this.hook = hook;
    this.field = field;       // "name" | "shortcut"
    this.prevValue = prevValue;
    this.newValue = newValue;
  }

  async undo() {
    this.hook.pushEvent("restore_flow_meta", {
      field: this.field,
      value: this.prevValue
    });
  }

  async redo() {
    this.hook.pushEvent("restore_flow_meta", {
      field: this.field,
      value: this.newValue
    });
  }
}
```

### 3.2 Server: `restore_flow_meta` event

```elixir
def handle_event("restore_flow_meta", %{"field" => field, "value" => value}, socket)
    when field in ["name", "shortcut"] do
  with_auth(socket, :edit_content, fn ->
    flow = socket.assigns.flow
    attrs = %{String.to_existing_atom(field) => value}
    case Flows.update_flow(flow, attrs) do
      {:ok, updated_flow} ->
        assign(socket, :flow, updated_flow)
      {:error, _} ->
        put_flash(socket, :error, "...")
    end
  end)
end
```

### 3.3 Recording Point

In the existing `handle_save_name` and `handle_save_shortcut` handlers, after successful update, push a JS event with the old and new values.

---

## Phase 4 — Robustness & Edge Cases

### 4.1 Hub Deletion Cascade: Replace `flow_updated` with Targeted Updates

When a hub is deleted and orphaned jumps exist, instead of broadcasting `flow_updated` (which clears history):

1. Delete the hub node → push `node_removed` (self: true)
2. For each orphaned jump, reset its `target_hub_id` → push `node_updated` per jump
3. Optionally mark jumps as "broken" with a visual indicator

This preserves the history stack. The `DeleteNodeAction` for the hub can be extended to store the hub's data and the orphaned jump state so undo can fully restore.

### 4.2 History Stack Size Limit

`HistoryPlugin` doesn't have a built-in max size. Add a cap:

```js
// After adding to history, trim if needed:
const MAX_HISTORY = 50;
// HistoryPlugin stores internally; we may need to fork or wrap
```

If the plugin doesn't expose trimming, wrap `history.add()` to track count and call `history.clear()` + re-add last N entries. Alternatively, accept unbounded for now (typical sessions don't exceed 50 meaningful actions).

### 4.3 Collaboration Conflict: Concurrent Edits to Same Node

If user A edits a node's text and user B simultaneously edits the same node, user A's undo would overwrite user B's change.

**Mitigation:** The collaboration locking system already prevents two users from editing the same node simultaneously. If a node is locked by another user, `persist_node_update` should reject the edit. The `restore_node_data` handler should check the same lock.

### 4.4 Deleted Node Data Restore

If a user edits a node, then deletes it, then tries to undo the edit — the node no longer exists. The `restore_node_data` event would fail.

**Mitigation:** In `restore_node_data`, check if the node is soft-deleted. If so, first restore it (clear `deleted_at`), then apply the data. Push both `node_restored` and `node_data_changed` events.

Alternatively, **skip the action silently** — if the undo stack has both a delete and a data edit, the user will undo the delete first (since it's more recent), which restores the node, and then undo the data edit.

---

## Summary

| Phase   | Operations                                       | Mechanism                                                  | Complexity  |
|---------|--------------------------------------------------|------------------------------------------------------------|-------------|
| 1       | Node create, duplicate                           | `CreateNodeAction` → reuse soft-delete/restore             | Low         |
| 2       | All node property edits                          | `NodeDataAction` + server `restore_node_data` + coalescing | Medium-High |
| 3       | Flow name, shortcut                              | `FlowMetaAction` + server `restore_flow_meta`              | Low         |
| 4       | Hub cascade fix, stack limits, conflict handling | Targeted `node_updated` instead of `flow_updated`          | Medium      |

### Files Modified

| File                                                                | Changes                                                                               |
|---------------------------------------------------------------------|---------------------------------------------------------------------------------------|
| `assets/js/flow_canvas/history_preset.js`                           | Add `CreateNodeAction`, `NodeDataAction`, `FlowMetaAction`                            |
| `assets/js/flow_canvas/handlers/editor_handlers.js`                 | Record create/duplicate in `handleNodeAdded`                                          |
| `assets/js/flow_canvas/event_bindings.js`                           | Handle `node_data_changed` and `flow_meta_changed` events                             |
| `lib/storyarn_web/live/flow_live/helpers/node_helpers.ex`           | Emit `node_data_changed` from `persist_node_update`, add `self: true` to `node_added` |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Add `restore_node_data` and `restore_flow_meta` handlers                              |
| `lib/storyarn_web/live/flow_live/show.ex`                           | Wire new events to handlers                                                           |

### Verification

```bash
# After each phase:
mix compile --warnings-as-errors
mix test

# Manual testing:
# 1. Create node → Ctrl+Z should delete it → Ctrl+Y should restore it
# 2. Edit dialogue text → Ctrl+Z should revert text → Ctrl+Y should re-apply
# 3. Rapid typing → should coalesce into single undo step
# 4. Delete node → undo → redo → verify node state is correct
# 5. Two users: verify locking prevents undo conflicts
```
