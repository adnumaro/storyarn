import type {
  ConnectionRemovedPayload,
  ConnectionServerPayload,
  ConnectionUpdatedPayload,
  FlowMetaChangedPayload,
  FlowUpdatedPayload,
  NodeDataChangedPayload,
  NodeMovedPayload,
  NodeRemovedPayload,
  NodeReparentedPayload,
  NodeRestoredPayload,
  NodeServerPayload,
  NodeUpdatedPayload,
  SequenceConfigUpdatedPayload,
  SequenceRenamedPayload,
} from "../services/editorHandlers";
import type {
  DebugHighlightConnectionsData,
  DebugHighlightNodeData,
  DebugUpdateBreakpointsData,
} from "../services/debug";
import type { FlowCanvasRuntime } from "./flowCanvasRuntime";

export function setupFlowCanvasServerEvents(runtime: FlowCanvasRuntime): void {
  if (!runtime.editorHandlers) {
    return;
  }

  const { handleEvent } = runtime.hookProxy;

  handleEvent("flow_updated", (data) =>
    runtime.editorHandlers!.handleFlowUpdated(data as FlowUpdatedPayload),
  );

  runtime.nodeMoveQueue = Promise.resolve();
  handleEvent("node_moved", (raw) => {
    if (!runtime.nodeMoveQueue) {
      return;
    }
    const data = raw as unknown as NodeMovedPayload;
    runtime.nodeMoveQueue = runtime.nodeMoveQueue
      .then(() => {
        if (!runtime.area || runtime.destroyed) {
          return;
        }
        return runtime.editorHandlers!.handleNodeMoved(data);
      })
      .catch(() => {});
  });

  handleEvent("node_reparented", (raw) => {
    if (runtime.destroyed) {
      return;
    }
    runtime.editorHandlers!.handleNodeReparented(raw as unknown as NodeReparentedPayload);
  });

  handleEvent("sequence_renamed", (raw) => {
    if (runtime.destroyed) {
      return;
    }
    runtime.editorHandlers!.handleSequenceRenamed(raw as unknown as SequenceRenamedPayload);
  });

  handleEvent("sequence_config_updated", (raw) => {
    if (runtime.destroyed) {
      return;
    }
    runtime.editorHandlers!.handleSequenceConfigUpdated(
      raw as unknown as SequenceConfigUpdatedPayload,
    );
  });

  handleEvent("node_added", (data) => {
    if (runtime.destroyed) {
      return;
    }
    runtime.editorHandlers!.handleNodeAdded(data as unknown as NodeServerPayload);
  });

  handleEvent("node_removed", (data) => {
    if (runtime.destroyed) {
      return;
    }
    runtime.editorHandlers!.handleNodeRemoved(data as unknown as NodeRemovedPayload);
  });

  handleEvent("node_restored", (data) => {
    if (runtime.destroyed) {
      return;
    }
    runtime.editorHandlers!.handleNodeRestored(data as unknown as NodeRestoredPayload);
  });

  runtime.nodeUpdateQueue = Promise.resolve();
  handleEvent("node_updated", (raw) => {
    if (!runtime.nodeUpdateQueue) {
      return;
    }
    const data = raw as unknown as NodeUpdatedPayload;
    runtime.nodeUpdateQueue = runtime.nodeUpdateQueue
      .then(async () => {
        if (!runtime.area || runtime.destroyed) {
          return;
        }
        await runtime.editorHandlers!.handleNodeUpdated(data);
        syncToolbarAfterNodeUpdated(runtime, data);
      })
      .catch(() => {});
  });

  handleEvent("node_data_changed", (data) =>
    runtime.editorHandlers!.handleNodeDataChanged(data as unknown as NodeDataChangedPayload),
  );
  handleEvent("flow_meta_changed", (data) =>
    runtime.editorHandlers!.handleFlowMetaChanged(data as unknown as FlowMetaChangedPayload),
  );
  handleEvent("connection_added", (data) =>
    runtime.editorHandlers!.handleConnectionAdded(data as unknown as ConnectionServerPayload),
  );
  handleEvent("connection_removed", (data) =>
    runtime.editorHandlers!.handleConnectionRemoved(data as unknown as ConnectionRemovedPayload),
  );
  handleEvent("connection_updated", (data) =>
    runtime.editorHandlers!.handleConnectionUpdated(data as unknown as ConnectionUpdatedPayload),
  );

  setupNavigationEvents(runtime);
  setupDebugEvents(runtime);
}

function syncToolbarAfterNodeUpdated(runtime: FlowCanvasRuntime, data: NodeUpdatedPayload): void {
  const { toolbarState } = runtime;
  if (!toolbarState.nodeId || String(data.id) !== String(toolbarState.nodeId)) {
    return;
  }

  const reteNode = runtime.nodeMap.get(data.id);
  if (reteNode) {
    toolbarState.nodeData = { ...reteNode.nodeData };
  }
}

function setupNavigationEvents(runtime: FlowCanvasRuntime): void {
  if (!runtime.navigationHandler) {
    return;
  }

  const { handleEvent } = runtime.hookProxy;
  handleEvent("navigate_to_hub", (data) =>
    runtime.navigationHandler!.navigateToHub(data.jump_db_id as number),
  );
  handleEvent("navigate_to_node", (data) =>
    runtime.navigationHandler!.navigateToNode(data.node_db_id as number),
  );
  handleEvent("navigate_to_jumps", (data) =>
    runtime.navigationHandler!.navigateToJumps(data.hub_db_id as number),
  );
  handleEvent("navigate_to_connection", (data) =>
    runtime.navigationHandler!.navigateToConnection({
      sourceDbId: data.source_node_id as number,
      sourcePin: (data.source_pin as string | null) ?? null,
      targetDbId: data.target_node_id as number,
      targetPin: (data.target_pin as string | null) ?? null,
    }),
  );
}

function setupDebugEvents(runtime: FlowCanvasRuntime): void {
  if (!runtime.debugHandler) {
    return;
  }

  const { handleEvent } = runtime.hookProxy;
  handleEvent("debug_highlight_node", (data) =>
    runtime.debugHandler!.handleHighlightNode(data as unknown as DebugHighlightNodeData),
  );
  handleEvent("debug_highlight_connections", (data) =>
    runtime.debugHandler!.handleHighlightConnections(
      data as unknown as DebugHighlightConnectionsData,
    ),
  );
  handleEvent("debug_update_breakpoints", (data) =>
    runtime.debugHandler!.handleUpdateBreakpoints(data as unknown as DebugUpdateBreakpointsData),
  );
  handleEvent("debug_clear_highlights", () => runtime.debugHandler!.handleClearHighlights());
}
