/**
 * Event handler bindings for the flow canvas.
 *
 * Sets up Rete.js area pipes and LiveView handleEvent bindings.
 */

/**
 * Sets up all event handlers for the flow canvas.
 * @param {Object} hook - The FlowCanvas hook instance
 */
export function setupEventHandlers(hook) {
  hook.selectedNodeId = null;
  hook.lastNodeClickTime = 0;
  hook.lastClickedNodeId = null;

  // Node position changes (drag) — skip during server-initiated loads
  hook.area.addPipe((context) => {
    if (context.type === "nodetranslated") {
      if (hook.isLoadingFromServer) return context;
      const node = hook.editor.getNode(context.data.id);
      if (node?.nodeId) {
        hook.editorHandlers.debounceNodeMoved(node.nodeId, context.data.position);
      }
    }
    return context;
  });

  // Node selection with double-click detection
  hook.area.addPipe((context) => {
    if (context.type === "nodepicked") {
      const node = hook.editor.getNode(context.data.id);
      if (node?.nodeId) {
        const now = Date.now();
        const isDoubleClick =
          hook.lastClickedNodeId === node.nodeId && now - hook.lastNodeClickTime < 300;

        hook.lastNodeClickTime = now;
        hook.lastClickedNodeId = node.nodeId;
        hook.selectedNodeId = node.nodeId;

        if (isDoubleClick) {
          hook.pushEvent("node_double_clicked", { id: node.nodeId });
        } else {
          hook.pushEvent("node_selected", { id: node.nodeId });
        }
      }
    }
    return context;
  });

  // Connection created
  hook.editor.addPipe((context) => {
    if (context.type === "connectioncreate" && !hook.isLoadingFromServer) {
      const conn = context.data;
      const sourceNode = hook.editor.getNode(conn.source);
      const targetNode = hook.editor.getNode(conn.target);

      if (sourceNode?.nodeId && targetNode?.nodeId) {
        hook.pushEvent("connection_created", {
          source_node_id: sourceNode.nodeId,
          source_pin: conn.sourceOutput,
          target_node_id: targetNode.nodeId,
          target_pin: conn.targetInput,
        });
      }
    }
    return context;
  });

  // Connection deleted
  hook.editor.addPipe((context) => {
    if (context.type === "connectionremove" && !hook.isLoadingFromServer) {
      const conn = context.data;
      const sourceNode = hook.editor.getNode(conn.source);
      const targetNode = hook.editor.getNode(conn.target);

      if (sourceNode?.nodeId && targetNode?.nodeId) {
        hook.pushEvent("connection_deleted", {
          source_node_id: sourceNode.nodeId,
          target_node_id: targetNode.nodeId,
        });
      }
    }
    return context;
  });

  // Handle server events - Editor
  hook.handleEvent("flow_updated", (data) => hook.editorHandlers.handleFlowUpdated(data));
  hook.handleEvent("node_added", (data) => hook.editorHandlers.handleNodeAdded(data));
  hook.handleEvent("node_removed", (data) => hook.editorHandlers.handleNodeRemoved(data));
  // Serialize node_updated events to prevent race conditions when
  // multiple response additions/deletions trigger concurrent rebuilds
  hook._nodeUpdateQueue = Promise.resolve();
  hook.handleEvent("node_updated", (data) => {
    hook._nodeUpdateQueue = hook._nodeUpdateQueue
      .then(() => hook.editorHandlers.handleNodeUpdated(data))
      .catch((err) => console.error("node_updated handler error:", err));
  });
  hook.handleEvent("connection_added", (data) => hook.editorHandlers.handleConnectionAdded(data));
  hook.handleEvent("connection_removed", (data) =>
    hook.editorHandlers.handleConnectionRemoved(data),
  );
  hook.handleEvent("connection_updated", (data) =>
    hook.editorHandlers.handleConnectionUpdated(data),
  );

  // Handle server events - Navigation (from panel buttons)
  hook.handleEvent("navigate_to_hub", (data) => {
    hook.navigationHandler.navigateToHub(data.jump_db_id);
  });
  hook.handleEvent("navigate_to_node", (data) => {
    hook.navigationHandler.navigateToNode(data.node_db_id);
  });
  hook.handleEvent("navigate_to_jumps", (data) => {
    hook.navigationHandler.navigateToJumps(data.hub_db_id);
  });

  // Navigation events (composed from storyarn-node Shadow DOM)
  hook.el.addEventListener("navigate-to-hub", (e) => {
    hook.navigationHandler.navigateToHub(e.detail.jumpDbId);
  });

  hook.el.addEventListener("navigate-to-jumps", (e) => {
    hook.navigationHandler.navigateToJumps(e.detail.hubDbId);
  });

  // Handle server events - Collaboration
  hook.handleEvent("cursor_update", (data) => hook.cursorHandler.handleCursorUpdate(data));
  hook.handleEvent("cursor_leave", (data) => hook.cursorHandler.handleCursorLeave(data));
  hook.handleEvent("locks_updated", (data) => hook.lockHandler.handleLocksUpdated(data));
}
