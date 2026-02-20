# 06 — Canvas Auto-Layout

> **Gap Reference:** Gap 2 from `COMPLEX_NARRATIVE_STRESS_TEST.md`
> **Priority:** HIGH
> **Effort:** Medium
> **Dependencies:** None
> **Previous:** `05_FLOW_TAGS.md`
> **Next:** `07_BETTER_SEARCH.md`
> **Last Updated:** February 20, 2026

---

## Context

Large flows (especially imported ones like the 806 Planescape: Torment dialogues with up to 743 nodes each) need automatic layout. Currently all node positioning is manual via drag-and-drop. An auto-layout algorithm would arrange nodes in a readable directed graph structure, saving massive amounts of manual work and making imported flows immediately usable.

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

### Node Positions: `assets/js/hooks/flow_canvas.js`

- Nodes loaded from server have `position_x`/`position_y` stored in the `flow_nodes` table.
- `addNodeToEditor(nodeData)` creates a `FlowNode` and calls either `view.translate(x, y)` (bulk load) or `area.translate(node.id, {x, y})` (interactive).
- `nodeMap` is `Map<server_id, FlowNode>` for server-to-Rete ID mapping.
- Node IDs in Rete use the format `node-${serverNodeId}` (string).

### Position Persistence: Server-Side

- `"node_moved"` event in `show.ex` line 369 dispatches to `GenericNodeHandlers.handle_node_moved/2`.
- Handler calls `Flows.update_node_position(node, %{position_x: x, position_y: y})`.
- Single-node update only. No batch position update endpoint exists.

### Undo/Redo: `assets/js/flow_canvas/history_preset.js`

- `DragAction` records `prev` and `next` positions per node.
- Uses `area.translate()` for undo/redo (fires through the pipe chain, triggers debounced server push).
- History uses coalescing: recent drags on the same node merge into one action.

### Dependencies: `assets/package.json`

No layout library installed. Current JS dependencies include `rete`, `rete-area-plugin`, `rete-connection-plugin`, `rete-history-plugin`, `rete-minimap-plugin`, `lit`, `lucide`, `sortablejs`, `@tiptap/*`.

### LOD System: `assets/js/flow_canvas/lod_controller.js`

Already implemented with two tiers (`full` and `simplified`). Bulk operations start in `simplified` LOD for performance.

---

## Subtask 1: Install dagre npm Package

**Goal:** Add the dagre graph layout library to the project dependencies.

### Files Affected

| File                  | Action                          |
|-----------------------|---------------------------------|
| `assets/package.json` | Add `@dagrejs/dagre` dependency |

### Implementation Steps

1. **Install dagre:**

```bash
cd assets && npm install @dagrejs/dagre
```

Note: Use `@dagrejs/dagre` (the maintained fork) rather than the original `dagre` package which is unmaintained. The API is identical.

2. **Verify installation:**

```bash
cd assets && node -e "const dagre = require('@dagrejs/dagre'); console.log('dagre version:', dagre.graphlib.Graph ? 'OK' : 'FAIL')"
```

### Test Battery

No automated test. Manual verification:

- `package.json` contains `"@dagrejs/dagre"` in dependencies.
- `npm ls @dagrejs/dagre` shows the installed version without errors.

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 2: Create `auto_layout.js` Module

**Goal:** Create a pure-function module that takes nodes and connections from the Rete editor and returns a position map using dagre's directed graph layout algorithm.

### Files Affected

| File                                   | Action   |
|----------------------------------------|----------|
| `assets/js/flow_canvas/auto_layout.js` | New file |

### Implementation Steps

1. **Create `assets/js/flow_canvas/auto_layout.js`:**

```javascript
/**
 * Auto-layout for flow canvas using dagre (directed graph layout).
 *
 * Takes the current editor state (nodes + connections) and returns a
 * Map of nodeId -> {x, y} positions arranged as a top-to-bottom DAG.
 *
 * Pure function — does not modify the editor. Caller applies positions.
 */

import dagre from "@dagrejs/dagre";

/**
 * Default layout options.
 * rankdir: TB (top-to-bottom), LR (left-to-right)
 * ranksep: vertical spacing between ranks (layers)
 * nodesep: horizontal spacing between nodes in the same rank
 */
const DEFAULT_OPTIONS = {
  rankdir: "LR",
  ranksep: 120,
  nodesep: 60,
  edgesep: 30,
  marginx: 40,
  marginy: 40,
};

/**
 * Approximate node dimensions by type.
 * These match the rendered sizes in storyarn_node.js.
 */
const NODE_DIMENSIONS = {
  dialogue: { width: 220, height: 120 },
  condition: { width: 200, height: 100 },
  instruction: { width: 200, height: 80 },
  hub: { width: 160, height: 60 },
  jump: { width: 160, height: 60 },
  entry: { width: 140, height: 50 },
  exit: { width: 140, height: 50 },
  subflow: { width: 200, height: 80 },
  scene: { width: 200, height: 80 },
  default: { width: 180, height: 80 },
};

/**
 * Computes auto-layout positions for all nodes in the editor.
 *
 * @param {NodeEditor} editor - The Rete NodeEditor instance
 * @param {Map} nodeMap - Map<serverId, FlowNode> for server ID lookup
 * @param {Object} [options] - Layout options (rankdir, ranksep, nodesep)
 * @returns {Map<string, {x: number, y: number}>} Map of Rete node ID -> new position
 */
export function computeAutoLayout(editor, nodeMap, options = {}) {
  const opts = { ...DEFAULT_OPTIONS, ...options };

  const g = new dagre.graphlib.Graph();
  g.setGraph({
    rankdir: opts.rankdir,
    ranksep: opts.ranksep,
    nodesep: opts.nodesep,
    edgesep: opts.edgesep,
    marginx: opts.marginx,
    marginy: opts.marginy,
  });
  g.setDefaultEdgeLabel(() => ({}));

  // Add nodes to dagre graph
  for (const node of editor.getNodes()) {
    const dims = NODE_DIMENSIONS[node.nodeType] || NODE_DIMENSIONS.default;
    g.setNode(node.id, { width: dims.width, height: dims.height });
  }

  // Add edges (connections) to dagre graph
  for (const conn of editor.getConnections()) {
    g.setEdge(conn.source, conn.target);
  }

  // Run layout
  dagre.layout(g);

  // Build position map
  const positions = new Map();
  for (const nodeId of g.nodes()) {
    const layoutNode = g.node(nodeId);
    if (layoutNode) {
      // dagre gives center positions; convert to top-left for Rete
      const dims = NODE_DIMENSIONS[editor.getNode(nodeId)?.nodeType] || NODE_DIMENSIONS.default;
      positions.set(nodeId, {
        x: layoutNode.x - dims.width / 2,
        y: layoutNode.y - dims.height / 2,
      });
    }
  }

  return positions;
}

/**
 * Collects the current positions of all nodes (for undo snapshot).
 *
 * @param {AreaPlugin} area - The Rete AreaPlugin instance
 * @param {NodeEditor} editor - The Rete NodeEditor instance
 * @returns {Map<string, {x: number, y: number}>} Map of Rete node ID -> current position
 */
export function captureCurrentPositions(area, editor) {
  const positions = new Map();
  for (const node of editor.getNodes()) {
    const view = area.nodeViews.get(node.id);
    if (view) {
      positions.set(node.id, { x: view.position.x, y: view.position.y });
    }
  }
  return positions;
}
```

### Test Battery

No server-side test (pure JS). Manual verification:

- Import `computeAutoLayout` in a test script or browser console.
- Verify it returns a `Map` with positions for all nodes.
- Verify dagre does not throw on empty graphs or disconnected nodes.

A basic assertion test can be added to a JS test runner if one exists:

```javascript
// Pseudo-test (adapt to project's JS test framework if available)
import { computeAutoLayout } from "./auto_layout.js";
// Create mock editor with getNodes/getConnections
// Assert positions map has correct size and valid x/y values
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 3: Wire Auto-Layout to Flow Canvas

**Goal:** Add an "Auto-layout" button to the flow header toolbar. When clicked, compute layout client-side, apply positions visually, then batch-push all new positions to the server.

### Files Affected

| File                                                        | Action                          |
|-------------------------------------------------------------|---------------------------------|
| `lib/storyarn_web/live/flow_live/components/flow_header.ex` | Add "Auto-layout" button        |
| `assets/js/hooks/flow_canvas.js`                            | Add `handleAutoLayout` method   |
| `assets/js/flow_canvas/event_bindings.js`                   | Bind `auto_layout` server event |

### Implementation Steps

1. **Add button to `flow_header.ex`:**

In the right side of the header (near the "Add Node" dropdown), add:

```elixir
<button
  :if={@can_edit}
  type="button"
  class="btn btn-ghost btn-sm gap-2"
  phx-click="auto_layout"
  title={dgettext("flows", "Auto-arrange all nodes")}
>
  <.icon name="layout-grid" class="size-4" />
  {dgettext("flows", "Layout")}
</button>
```

Place it before the Debug button, after the Play link.

2. **Add event handler to `show.ex`:**

```elixir
def handle_event("auto_layout", _params, socket) do
  with_auth(:edit_content, socket, fn ->
    # Layout computation happens on the client; this event just tells the client to run it.
    # The client will push batch_update_positions back.
    {:noreply, push_event(socket, "trigger_auto_layout", %{})}
  end)
end
```

3. **Add client-side handler in `flow_canvas.js`:**

Add a method to the FlowCanvas hook:

```javascript
async performAutoLayout() {
  const { computeAutoLayout, captureCurrentPositions } = await import(
    "../flow_canvas/auto_layout.js"
  );

  // Snapshot current positions for undo
  const prevPositions = captureCurrentPositions(this.area, this.editor);

  // Compute new layout
  const newPositions = computeAutoLayout(this.editor, this.nodeMap);

  // Apply positions visually
  for (const [reteNodeId, pos] of newPositions) {
    await this.area.translate(reteNodeId, pos);
  }

  // Fit view to new layout
  const { AreaExtensions } = await import("rete-area-plugin");
  await AreaExtensions.zoomAt(this.area, this.editor.getNodes());

  // Build batch payload: map Rete IDs back to server IDs
  const batchPositions = [];
  for (const [reteNodeId, pos] of newPositions) {
    // reteNodeId format is "node-{serverId}"
    const serverId = reteNodeId.replace("node-", "");
    batchPositions.push({
      id: parseInt(serverId, 10),
      position_x: pos.x,
      position_y: pos.y,
    });
  }

  // Push batch to server
  this.pushEvent("batch_update_positions", { positions: batchPositions });

  // Record undo action
  if (this.history) {
    this.history.add(new AutoLayoutAction(this, prevPositions, newPositions));
  }
}
```

4. **Bind the server event in `event_bindings.js`:**

Add after the existing `handleEvent` bindings:

```javascript
hook.handleEvent("trigger_auto_layout", () => hook.performAutoLayout());
```

5. **Create `AutoLayoutAction` class in `history_preset.js`:**

See Subtask 5 for the full implementation. For now, the layout works without undo.

### Test Battery

No server-side test for the client computation. Test the server event handling:

**File:** `test/storyarn_web/live/flow_live/auto_layout_test.exs`

```elixir
defmodule StoryarnWeb.FlowLive.AutoLayoutTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    project = project_fixture(workspace)
    flow = flow_fixture(project)
    %{user: user, workspace: workspace, project: project, flow: flow}
  end

  describe "auto_layout event" do
    test "triggers auto_layout push event for authorized users", %{
      conn: conn, user: user, workspace: workspace, project: project, flow: flow
    } do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")

      # The event should not crash; it triggers a client-side push_event
      assert render_hook(view, "auto_layout", %{})
    end
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 4: Server Handler for Batch Position Update

**Goal:** Add a `batch_update_positions` event handler that updates multiple node positions in a single transaction. This avoids N individual `node_moved` events after auto-layout.

### Files Affected

| File                                                                | Action                                            |
|---------------------------------------------------------------------|---------------------------------------------------|
| `lib/storyarn_web/live/flow_live/show.ex`                           | Add `"batch_update_positions"` event handler      |
| `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex` | Add `handle_batch_update_positions/2`             |
| `lib/storyarn/flows/node_crud.ex`                                   | Add `batch_update_positions/2` (or in NodeUpdate) |
| `lib/storyarn/flows.ex`                                             | Expose via `defdelegate`                          |

### Implementation Steps

1. **Add to `lib/storyarn/flows/node_crud.ex`** (or `lib/storyarn/flows/node_update.ex` if NodeUpdate exists as a separate module):

```elixir
@doc """
Batch-updates positions for multiple nodes in a single transaction.
Accepts a list of maps with :id, :position_x, :position_y.
Returns {:ok, count} with the number of updated nodes.
"""
def batch_update_positions(flow_id, positions) when is_list(positions) do
  Repo.transaction(fn ->
    Enum.each(positions, fn %{id: node_id, position_x: x, position_y: y} ->
      from(n in FlowNode,
        where: n.id == ^node_id and n.flow_id == ^flow_id and is_nil(n.deleted_at)
      )
      |> Repo.update_all(set: [position_x: x, position_y: y, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)])
    end)

    length(positions)
  end)
end
```

Note: This validates that each node belongs to the given flow (security). Uses `update_all` per node for simplicity. For very large flows (1000+ nodes), consider a single raw SQL `UPDATE ... FROM unnest(...)` query. YAGNI for now.

2. **Add delegation in `lib/storyarn/flows.ex`:**

```elixir
@doc """
Batch-updates positions for multiple nodes. Used by auto-layout.
"""
@spec batch_update_positions(integer(), [map()]) :: {:ok, integer()} | {:error, term()}
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
@spec handle_batch_update_positions(map(), Phoenix.LiveView.Socket.t()) ::
        {:noreply, Phoenix.LiveView.Socket.t()}
def handle_batch_update_positions(%{"positions" => positions}, socket) when is_list(positions) do
  flow = socket.assigns.flow

  # Parse positions into the expected format
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

      # Should not crash, but the node should not be updated
      assert {:ok, 1} = Flows.batch_update_positions(flow.id, positions)

      # Node in the other flow should remain at original position
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

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 5: Integration with Undo/Redo

**Goal:** Make the auto-layout operation undoable as a single action. Undo restores all nodes to their pre-layout positions; redo re-applies the layout.

### Files Affected

| File                                      | Action                                                                     |
|-------------------------------------------|----------------------------------------------------------------------------|
| `assets/js/flow_canvas/history_preset.js` | Add `AutoLayoutAction` class, export it                                    |
| `assets/js/hooks/flow_canvas.js`          | Use `AutoLayoutAction` in `performAutoLayout` (already wired in Subtask 3) |

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
    for (const [reteNodeId, pos] of positions) {
      const view = this.hook.area.nodeViews.get(reteNodeId);
      if (view) {
        await this.hook.area.translate(reteNodeId, pos);
      }
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

2. **Export the class:**

Add to the existing exports at the bottom of `history_preset.js`:

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

3. **Import in `flow_canvas.js`:**

The `performAutoLayout` method (from Subtask 3) already imports and uses `AutoLayoutAction`. Update the import:

```javascript
import { AutoLayoutAction } from "../flow_canvas/history_preset.js";
```

Or use dynamic import inside `performAutoLayout` to keep the import lazy:

```javascript
const { AutoLayoutAction } = await import("../flow_canvas/history_preset.js");
```

4. **Guard against recording during undo/redo:**

The `_applyPositions` method calls `area.translate()` which fires through the `nodetranslated` pipe and the existing DragAction coalescing logic. To prevent these from recording individual drag actions during undo/redo of auto-layout:

Wrap the apply in `enterLoadingFromServer` / `exitLoadingFromServer`:

```javascript
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
```

The `isLoadingFromServer` guard in the history preset's nodetranslated handler will skip recording individual drags. The `debounceNodeMoved` in event_bindings.js also checks `isLoadingFromServer`, so individual node_moved events will not fire either.

### Test Battery

No server-side test for undo/redo (client-side history). Manual verification:

1. Open a flow with multiple nodes.
2. Click "Layout" button.
3. Verify nodes are rearranged.
4. Press Ctrl+Z (undo).
5. Verify all nodes return to their previous positions.
6. Press Ctrl+Shift+Z (redo).
7. Verify nodes return to the layout positions.
8. Verify that after undo and redo, refreshing the page shows the correct positions (server persisted).

Automated E2E test (Playwright):

**File:** `test/e2e/flow_auto_layout_test.exs` (or equivalent Playwright test file)

```elixir
# Pseudo-test — adapt to your E2E framework
# 1. Navigate to a flow with 3+ nodes
# 2. Note initial positions
# 3. Click "Layout" button
# 4. Assert positions have changed
# 5. Press Ctrl+Z
# 6. Assert positions match original
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary

| Subtask                  | What it delivers                        | Can be used independently?                               |
|--------------------------|-----------------------------------------|----------------------------------------------------------|
| 1. Install dagre         | Layout library available                | Yes (dependency ready)                                   |
| 2. `auto_layout.js`      | Pure layout computation function        | Yes (reusable by import script)                          |
| 3. Wire to flow canvas   | "Layout" button applies layout visually | Yes (positions updated client-side + persisted per-node) |
| 4. Batch position update | Efficient server persistence            | Yes (replaces N individual updates with 1 transaction)   |
| 5. Undo/redo integration | Layout is reversible                    | Yes (clean undo experience)                              |

### Import Script Note

Subtask 2 creates `computeAutoLayout` as a pure function. The future Planescape: Torment import script (Phase D in the stress test plan) can call this function directly after creating nodes, before persisting positions. The function operates on in-memory data structures and does not require a live Rete editor. For server-side import scripts, consider porting the dagre call to Elixir or running it via Node.js as a build step.

Alternatively, the import script can:
1. Create all nodes with default positions (0, 0).
2. Open the flow in the browser.
3. Click "Auto-layout" (leveraging the existing button).
4. Save.

This manual step is acceptable for a one-off import validation.

**Next document:** [07_BETTER_SEARCH.md](./07_BETTER_SEARCH.md)
