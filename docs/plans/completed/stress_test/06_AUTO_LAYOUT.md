# 06 — Canvas Auto-Layout

> **Gap Reference:** Gap 2 from `COMPLEX_NARRATIVE_STRESS_TEST.md`
> **Priority:** HIGH
> **Effort:** Low–Medium
> **Dependencies:** None
> **Previous:** `05_FLOW_TAGS.md` (discarded)
> **Next:** `07_BETTER_SEARCH.md`
> **Last Updated:** February 21, 2026

---

## Context

Large flows (especially imported ones like the 806 Planescape: Torment dialogues with up to 743 nodes each) need automatic layout. Currently all node positioning is manual via drag-and-drop. An auto-layout algorithm would arrange nodes in a readable directed graph structure, saving massive amounts of manual work and making imported flows immediately usable.

**Approach:** Use the official [`rete-auto-arrange-plugin`](https://retejs.org/docs/guides/arrange) which wraps [ELK (Eclipse Layout Kernel)](https://www.eclipse.org/elk/) via `elkjs`. This replaces the dagre-based custom approach — the official plugin handles graph construction, layout computation, and position application natively, reducing our code to plugin setup + event wiring.

## Current State

### Plugin Architecture: `assets/js/flow_canvas/setup.js`

Creates and configures all Rete.js plugins:

```javascript
const editor = new NodeEditor();
const area = new AreaPlugin(container);
const connection = new ConnectionPlugin();
const history = new HistoryPlugin({ timing: 200 });
const minimap = new MinimapPlugin();
const render = new LitPlugin();
```

`finalizeSetup` calls `AreaExtensions.zoomAt(area, editor.getNodes())` to fit the view after loading.

### Node Dimensions: `assets/js/flow_canvas/flow_node.js`

`FlowNode` has static properties `width = 190` and `height = 130`. The auto-arrange plugin reads these to compute layout spacing.

### Node Positions: `assets/js/hooks/flow_canvas.js`

- Nodes loaded from server have `position_x`/`position_y` stored in the `flow_nodes` table.
- `addNodeToEditor(nodeData)` creates a `FlowNode` and calls either `view.translate(x, y)` (bulk load) or `area.translate(node.id, {x, y})` (interactive).
- `nodeMap` is `Map<server_id, FlowNode>` for server-to-Rete ID mapping.
- Node IDs in Rete use the format `node-${serverNodeId}` (string).

### Position Persistence: Server-Side

- `"node_moved"` event in `show.ex` dispatches to `GenericNodeHandlers.handle_node_moved/2`.
- Handler calls `Flows.update_node_position(node, %{position_x: x, position_y: y})`.
- Single-node update only. No batch position update endpoint exists.

### Undo/Redo: `assets/js/flow_canvas/history_preset.js`

- `DragAction` records `prev` and `next` positions per node.
- Uses `area.translate()` for undo/redo (fires through the pipe chain, triggers debounced server push).
- `enterLoadingFromServer()` / `exitLoadingFromServer()` with counter-based `isLoadingFromServer` getter guards against recording history during programmatic operations.
- History uses coalescing: recent drags on the same node merge into one action.

### LOD System: `assets/js/flow_canvas/lod_controller.js`

Already implemented with two tiers (`full` and `simplified`). Bulk operations start in `simplified` LOD for performance.

---

## Subtask 1: Install `rete-auto-arrange-plugin` and `elkjs`

**Goal:** Add the official Rete.js auto-arrange plugin and its ELK layout engine dependency.

### Files Affected

| File                  | Action                                           |
|-----------------------|--------------------------------------------------|
| `assets/package.json` | Add `rete-auto-arrange-plugin` and `elkjs` deps  |

### Implementation Steps

1. **Install packages:**

```bash
cd assets && npm install rete-auto-arrange-plugin elkjs
```

The `rete-auto-arrange-plugin` is the official Rete.js plugin (maintained by the Rete team). `elkjs` is the JavaScript port of Eclipse Layout Kernel — a mature, well-tested graph layout library supporting hierarchical, layered, and force-directed algorithms.

2. **Verify installation:**

```bash
cd assets && node -e "import('rete-auto-arrange-plugin').then(m => console.log('OK:', Object.keys(m)))"
```

### Test Battery

No automated test. Manual verification:

- `package.json` contains `"rete-auto-arrange-plugin"` and `"elkjs"` in dependencies.
- `npm ls rete-auto-arrange-plugin` and `npm ls elkjs` show installed versions without errors.

> Run `just quality` before proceeding.

---

## Subtask 2: Register Plugin in Setup + Add to Context Menu

**Goal:** Register the auto-arrange plugin in the Rete setup, add "Auto-layout" to the canvas right-click context menu, and wire the action to trigger layout computation.

The flow canvas already has a context menu via `ContextMenuPlugin` (`context_menu_items.js`). Right-clicking on empty canvas shows "Add node" + "Start debugging". We add "Auto-layout" there — no header button needed.

### Files Affected

| File                                            | Action                                  |
|-------------------------------------------------|-----------------------------------------|
| `assets/js/flow_canvas/setup.js`                | Register AutoArrangePlugin              |
| `assets/js/flow_canvas/context_menu_items.js`   | Add "Auto-layout" item to canvas menu   |
| `assets/js/hooks/flow_canvas.js`                | Add `performAutoLayout` method, store plugin ref |

### Implementation Steps

1. **Register plugin in `setup.js`:**

```javascript
import { AutoArrangePlugin, Presets as ArrangePresets } from "rete-auto-arrange-plugin";

// In createPlugins() or equivalent setup function:
const arrange = new AutoArrangePlugin();
arrange.addPreset(ArrangePresets.classic.setup());
area.use(arrange);
```

Return `arrange` alongside the other plugins so `flow_canvas.js` can store it on the hook.

2. **Store plugin reference in `flow_canvas.js`:**

```javascript
// In initEditor(), after setup:
this.arrange = arrange; // from setup return value
```

3. **Add "Auto-layout" to context menu in `context_menu_items.js`:**

In the `context === "root"` branch, add a new item alongside "Add node" and "Start debugging":

```javascript
import { LayoutGrid } from "lucide";

// At module level, with other icon constants:
const LAYOUT_ICON = createIconHTML(LayoutGrid, { size: ICON_SIZE });

// In the root context menu list:
if (context === "root") {
  return {
    searchBar: false,
    list: [
      // ... existing "Add node" submenu ...
      // ... existing "Start debugging" item ...
      {
        label: "Auto-layout",
        key: "auto_layout",
        icon: LAYOUT_ICON,
        handler: () => hook.performAutoLayout(),
      },
    ],
  };
}
```

Place it as the last item in the canvas menu. The label should use the hook's i18n if available: `hook.i18n?.auto_layout || "Auto-layout"`.

4. **Add `performAutoLayout` method to `flow_canvas.js`:**

```javascript
async performAutoLayout() {
  const { ArrangeAppliers } = await import("rete-auto-arrange-plugin");
  const { AreaExtensions } = await import("rete-area-plugin");

  // Snapshot current positions for undo
  const prevPositions = new Map();
  for (const node of this.editor.getNodes()) {
    const view = this.area.nodeViews.get(node.id);
    if (view) {
      prevPositions.set(node.id, { x: view.position.x, y: view.position.y });
    }
  }

  // Compute and apply layout with animation
  const applier = new ArrangeAppliers.TransitionApplier({
    duration: 400,
    timingFunction: (t) => t * (2 - t), // ease-out
  });

  this.enterLoadingFromServer(); // prevent history recording during layout
  try {
    await this.arrange.layout({
      applier,
      options: {
        "elk.algorithm": "layered",
        "elk.direction": "RIGHT",
        "elk.spacing.nodeNode": "60",
        "elk.layered.spacing.nodeNodeBetweenLayers": "120",
      },
    });
  } finally {
    this.exitLoadingFromServer();
  }

  // Fit view to new layout
  await AreaExtensions.zoomAt(this.area, this.editor.getNodes());

  // Collect new positions for persistence + undo
  const newPositions = new Map();
  for (const node of this.editor.getNodes()) {
    const view = this.area.nodeViews.get(node.id);
    if (view) {
      newPositions.set(node.id, { x: view.position.x, y: view.position.y });
    }
  }

  // Batch-persist to server
  const batchPositions = [];
  for (const [reteNodeId, pos] of newPositions) {
    const serverId = reteNodeId.replace("node-", "");
    batchPositions.push({
      id: parseInt(serverId, 10),
      position_x: pos.x,
      position_y: pos.y,
    });
  }
  this.pushEvent("batch_update_positions", { positions: batchPositions });

  // Record undo action (see Subtask 4)
  if (this.history) {
    const { AutoLayoutAction } = await import("../flow_canvas/history_preset.js");
    this.history.add(new AutoLayoutAction(this, prevPositions, newPositions));
  }
}
```

### ELK Layout Options

The `elk.direction` option controls graph orientation:
- `"RIGHT"` — left-to-right (default, best for dialogue flows)
- `"DOWN"` — top-to-bottom (alternative)

The `elk.algorithm` option selects the layout strategy:
- `"layered"` — hierarchical layered layout (best for directed flows)
- `"force"` — force-directed (better for undirected graphs)

`FlowNode.width` (190) and `FlowNode.height` (130) are automatically read by the plugin for spacing computation.

### Test Battery

Manual verification:
- Right-click on empty canvas area shows "Auto-layout" in the context menu.
- Clicking it rearranges all nodes with animation.
- Nodes land in a readable left-to-right directed graph structure.
- View zooms to fit after layout completes.
- No header button needed — action lives purely in the context menu.

> Run `just quality` before proceeding.

---

## Subtask 3: Server Handler for Batch Position Update

**Goal:** Add a `batch_update_positions` event handler that updates multiple node positions in a single transaction. This avoids N individual `node_moved` events after auto-layout.

### Files Affected

| File                                                                | Action                                        |
|---------------------------------------------------------------------|-----------------------------------------------|
| `lib/storyarn_web/live/flow_live/show.ex`                           | Add `"batch_update_positions"` event handler  |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Add `handle_batch_update_positions/2`         |
| `lib/storyarn/flows/node_crud.ex`                                   | Add `batch_update_positions/2`                |
| `lib/storyarn/flows.ex`                                             | Expose via `defdelegate`                      |

### Implementation Steps

1. **Add to `lib/storyarn/flows/node_crud.ex`:**

```elixir
@doc """
Batch-updates positions for multiple nodes in a single transaction.
Accepts a list of maps with :id, :position_x, :position_y.
Returns {:ok, count} with the number of updated nodes.
"""
def batch_update_positions(flow_id, positions) when is_list(positions) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  Repo.transaction(fn ->
    Enum.each(positions, fn %{id: node_id, position_x: x, position_y: y} ->
      from(n in FlowNode,
        where: n.id == ^node_id and n.flow_id == ^flow_id and is_nil(n.deleted_at)
      )
      |> Repo.update_all(set: [position_x: x, position_y: y, updated_at: now])
    end)

    length(positions)
  end)
end
```

Note: Validates that each node belongs to the given flow (security). Uses `update_all` per node for simplicity. For very large flows (1000+ nodes), consider a single raw SQL `UPDATE ... FROM unnest(...)` query. YAGNI for now.

2. **Add delegation in `lib/storyarn/flows.ex`:**

```elixir
defdelegate batch_update_positions(flow_id, positions), to: NodeCrud
```

3. **Add event handler in `show.ex`:**

```elixir
def handle_event("batch_update_positions", params, socket) do
  with_auth(:edit_content, socket, fn ->
    GenericNodeHandlers.handle_batch_update_positions(params, socket)
  end)
end
```

4. **Add handler in `generic_node_handlers.ex`:**

```elixir
def handle_batch_update_positions(%{"positions" => positions}, socket) when is_list(positions) do
  flow = socket.assigns.flow

  parsed =
    Enum.map(positions, fn pos ->
      %{
        id: pos["id"],
        position_x: pos["position_x"] / 1,
        position_y: pos["position_y"] / 1
      }
    end)

  case Flows.batch_update_positions(flow.id, parsed) do
    {:ok, _count} ->
      schedule_save_status_reset()

      {:noreply,
       socket
       |> assign(:save_status, :saved)
       |> CollaborationHelpers.broadcast_change(:flow_refresh, %{})}

    {:error, _reason} ->
      {:noreply,
       put_flash(socket, :error, dgettext("flows", "Could not update node positions."))}
  end
end

def handle_batch_update_positions(_params, socket), do: {:noreply, socket}
```

Note: After batch update, broadcasts `flow_refresh` so collaborators reload the updated positions. This is simpler than sending per-node position events for potentially hundreds of nodes.

### Test Battery

**File:** `test/storyarn/flows/batch_update_positions_test.exs`

```elixir
defmodule Storyarn.Flows.BatchUpdatePositionsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    project = project_fixture()
    flow = flow_fixture(project)
    %{project: project, flow: flow}
  end

  describe "batch_update_positions/2" do
    test "updates positions for multiple nodes", %{flow: flow} do
      node1 = node_fixture(flow, %{position_x: 0.0, position_y: 0.0})
      node2 = node_fixture(flow, %{position_x: 0.0, position_y: 0.0})

      positions = [
        %{id: node1.id, position_x: 100.0, position_y: 200.0},
        %{id: node2.id, position_x: 300.0, position_y: 400.0}
      ]

      assert {:ok, 2} = Flows.batch_update_positions(flow.id, positions)

      updated1 = Flows.get_node!(flow.id, node1.id)
      assert updated1.position_x == 100.0
      assert updated1.position_y == 200.0

      updated2 = Flows.get_node!(flow.id, node2.id)
      assert updated2.position_x == 300.0
      assert updated2.position_y == 400.0
    end

    test "ignores nodes from a different flow", %{project: project, flow: flow} do
      other_flow = flow_fixture(project)
      other_node = node_fixture(other_flow, %{position_x: 0.0, position_y: 0.0})

      positions = [
        %{id: other_node.id, position_x: 999.0, position_y: 999.0}
      ]

      assert {:ok, 1} = Flows.batch_update_positions(flow.id, positions)

      unchanged = Flows.get_node!(other_flow.id, other_node.id)
      assert unchanged.position_x == 0.0
      assert unchanged.position_y == 0.0
    end

    test "handles empty positions list", %{flow: flow} do
      assert {:ok, 0} = Flows.batch_update_positions(flow.id, [])
    end
  end
end
```

> Run `just quality` before proceeding.

---

## Subtask 4: Integration with Undo/Redo

**Goal:** Make the auto-layout operation undoable as a single action. Undo restores all nodes to their pre-layout positions; redo re-applies the layout.

### Files Affected

| File                                      | Action                                                                     |
|-------------------------------------------|----------------------------------------------------------------------------|
| `assets/js/flow_canvas/history_preset.js` | Add `AutoLayoutAction` class, export it                                    |
| `assets/js/hooks/flow_canvas.js`          | Use `AutoLayoutAction` in `performAutoLayout` (already wired in Subtask 2) |

### Implementation Steps

1. **Add `AutoLayoutAction` to `history_preset.js`:**

```javascript
/**
 * Undo/redo action for auto-layout.
 * Stores full position snapshots (before and after) for all nodes.
 * Undo applies previous positions; redo applies layout positions.
 * Both operations push batch_update_positions to persist.
 */
class AutoLayoutAction {
  constructor(hook, prevPositions, newPositions) {
    this.hook = hook;
    this.prevPositions = prevPositions; // Map<reteNodeId, {x, y}>
    this.newPositions = newPositions;   // Map<reteNodeId, {x, y}>
  }

  async undo() {
    await this._applyPositions(this.prevPositions);
  }

  async redo() {
    await this._applyPositions(this.newPositions);
  }

  async _applyPositions(positions) {
    this.hook.enterLoadingFromServer();
    try {
      for (const [reteNodeId, pos] of positions) {
        const view = this.hook.area.nodeViews.get(reteNodeId);
        if (view) {
          await this.hook.area.translate(reteNodeId, pos);
        }
      }
    } finally {
      this.hook.exitLoadingFromServer();
    }

    // Batch-persist to server
    const batchPositions = [];
    for (const [reteNodeId, pos] of positions) {
      const serverId = reteNodeId.replace("node-", "");
      batchPositions.push({
        id: parseInt(serverId, 10),
        position_x: pos.x,
        position_y: pos.y,
      });
    }
    this.hook.pushEvent("batch_update_positions", { positions: batchPositions });
  }
}
```

2. **Export the class** (add to existing exports at the bottom of `history_preset.js`):

```javascript
export {
  AutoLayoutAction,
  CreateNodeAction,
  DeleteNodeAction,
  FlowMetaAction,
  FLOW_META_COALESCE_MS,
  NodeDataAction,
  NODE_DATA_COALESCE_MS,
};
```

3. **Guard notes:**

The `enterLoadingFromServer()` / `exitLoadingFromServer()` wrapping in `_applyPositions` prevents the `nodetranslated` pipe from recording individual `DragAction` entries during undo/redo. The `isLoadingFromServer` guard in `event_bindings.js` also prevents individual `node_moved` events from firing — only the batch update at the end persists.

### Test Battery

Manual verification:

1. Open a flow with multiple nodes.
2. Click "Layout" button.
3. Verify nodes are rearranged with animation.
4. Press Ctrl+Z (undo).
5. Verify all nodes return to their previous positions.
6. Press Ctrl+Shift+Z (redo).
7. Verify nodes return to the layout positions.
8. Verify that after undo and redo, refreshing the page shows the correct positions (server persisted).

> Run `just quality` before proceeding.

---

## Summary

| Subtask                      | What it delivers                        | Can be used independently?                               |
|------------------------------|-----------------------------------------|----------------------------------------------------------|
| 1. Install plugin + elkjs    | Layout engine available                 | Yes (dependency ready)                                   |
| 2. Wire plugin to canvas     | "Layout" button applies layout visually | Yes (positions updated client-side + persisted per-node) |
| 3. Batch position update     | Efficient server persistence            | Yes (replaces N individual updates with 1 transaction)   |
| 4. Undo/redo integration     | Layout is reversible                    | Yes (clean undo experience)                              |

### Comparison with Previous dagre Approach

| Aspect              | dagre (old plan)                                | rete-auto-arrange-plugin (this plan)              |
|---------------------|-------------------------------------------------|---------------------------------------------------|
| Dependency          | `@dagrejs/dagre` (unmaintained fork)            | `rete-auto-arrange-plugin` + `elkjs` (official)   |
| Graph construction  | Manual: iterate nodes/connections, build dagre graph | Automatic: plugin reads from Rete editor          |
| Layout engine       | dagre (basic layered)                           | ELK (mature, multiple algorithms)                 |
| Position application| Manual: iterate results, call area.translate    | Built-in with `TransitionApplier` (animated)      |
| Node dimensions     | Manual per-type map (9 entries)                 | Reads `FlowNode.width`/`height` automatically     |
| Code to maintain    | ~60 lines in new `auto_layout.js`               | ~10 lines of plugin setup                         |
| Animation           | Not included (would need custom)                | Built-in `TransitionApplier`                      |

### Import Script Note

The auto-arrange plugin can be used after importing flows. The import workflow is:

1. Create all nodes with default positions (0, 0).
2. Open the flow in the browser.
3. Click "Layout" (leveraging the existing button).
4. Positions are auto-persisted to server.

For programmatic layout without a browser, `elkjs` can be used directly in a Node.js script with the same ELK options.

**Next document:** [07_BETTER_SEARCH.md](../../stress_test/07_BETTER_SEARCH.md)
