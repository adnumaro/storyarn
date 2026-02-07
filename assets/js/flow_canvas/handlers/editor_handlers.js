/**
 * Editor handlers for node and connection CRUD operations.
 */

import { ClassicPreset } from "rete";
import { FlowNode } from "../flow_node.js";
import { getNodeDef } from "../node_config.js";

/**
 * Creates the editor handlers with methods bound to the hook context.
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {Object} Handler methods
 */
export function createEditorHandlers(hook) {
  return {
    /**
     * Initializes debounce timers map.
     */
    init() {
      hook.debounceTimers = {};
    },

    /**
     * Debounces node position updates to avoid flooding the server.
     * @param {string|number} nodeId - The node ID
     * @param {Object} position - Position with x, y coordinates
     */
    debounceNodeMoved(nodeId, position) {
      if (hook.debounceTimers[nodeId]) {
        clearTimeout(hook.debounceTimers[nodeId]);
      }

      hook.debounceTimers[nodeId] = setTimeout(() => {
        hook.pushEvent("node_moved", {
          id: nodeId,
          position_x: position.x,
          position_y: position.y,
        });
        delete hook.debounceTimers[nodeId];
      }, 300);
    },

    /**
     * Handles complete flow update (reload all nodes/connections).
     * @param {Object} data - Flow data with nodes and connections
     */
    async handleFlowUpdated(data) {
      for (const conn of [...hook.editor.getConnections()]) {
        await hook.editor.removeConnection(conn.id);
      }
      for (const node of [...hook.editor.getNodes()]) {
        await hook.editor.removeNode(node.id);
      }
      hook.nodeMap.clear();
      hook.connectionDataMap.clear();
      await hook.loadFlow(data);
      await hook.rebuildHubsMap();
    },

    /**
     * Handles node added event from server.
     * @param {Object} data - Node data
     */
    async handleNodeAdded(data) {
      await hook.addNodeToEditor(data);
      if (data.type === "hub" || data.type === "jump") await hook.rebuildHubsMap();
    },

    /**
     * Handles node removed event from server.
     * @param {Object} data - Data with node id
     */
    async handleNodeRemoved(data) {
      const node = hook.nodeMap.get(data.id);
      if (node) {
        const needsHubRebuild = node.nodeType === "hub" || node.nodeType === "jump";
        await hook.editor.removeNode(node.id);
        hook.nodeMap.delete(data.id);
        if (hook.selectedNodeId === data.id) {
          hook.selectedNodeId = null;
        }
        if (needsHubRebuild) await hook.rebuildHubsMap();
      }
    },

    /**
     * Handles node updated event from server.
     * Uses per-type needsRebuild to determine if full rebuild is needed.
     * @param {Object} data - Data with id and nodeData
     */
    async handleNodeUpdated(data) {
      const { id, data: nodeData } = data;

      const existingNode = hook.nodeMap.get(id);
      if (!existingNode) {
        return;
      }

      // Check per-type needsRebuild
      const def = getNodeDef(existingNode.nodeType);
      const shouldRebuild = def?.needsRebuild?.(existingNode.nodeData, nodeData) || false;

      if (shouldRebuild) {
        await this.rebuildNode(id, existingNode, nodeData);
      } else {
        // Update nodeData with new reference to trigger Lit re-render
        existingNode.nodeData = { ...nodeData };
        existingNode._updateTs = Date.now();
        await hook.area.update("node", existingNode.id);
      }

      if (existingNode.nodeType === "hub" || existingNode.nodeType === "jump")
        await hook.rebuildHubsMap();
    },

    /**
     * Rebuilds a node preserving its connections.
     * Used when outputs change (responses, condition rules, etc.).
     * @param {string|number} id - The database node ID
     * @param {Object} existingNode - The existing Rete node
     * @param {Object} nodeData - The new node data
     */
    async rebuildNode(id, existingNode, nodeData) {
      const view = hook.area.nodeViews.get(existingNode.id);
      const position = view ? { ...view.position } : { x: 0, y: 0 };

      hook.enterLoadingFromServer();
      try {
        // Snapshot the array — getConnections() returns a mutable reference
        const connections = [...hook.editor.getConnections()];
        const affectedConnections = [];

        // Save and remove affected connections (including their metadata)
        for (const conn of connections) {
          if (conn.source === existingNode.id || conn.target === existingNode.id) {
            affectedConnections.push({
              source: hook.editor.getNode(conn.source)?.nodeId,
              sourceOutput: conn.sourceOutput,
              target: hook.editor.getNode(conn.target)?.nodeId,
              targetInput: conn.targetInput,
              connData: hook.connectionDataMap.get(conn.id),
            });
            hook.connectionDataMap.delete(conn.id);
            await hook.editor.removeConnection(conn.id);
          }
        }

        // Remove and recreate the node
        await hook.editor.removeNode(existingNode.id);
        hook.nodeMap.delete(id);

        const newNode = new FlowNode(existingNode.nodeType, id, nodeData);
        newNode.id = `node-${id}`;

        await hook.editor.addNode(newNode);
        await hook.area.translate(newNode.id, position);
        hook.nodeMap.set(id, newNode);

        // Force re-render to update visual
        await hook.area.update("node", newNode.id);

        // Restore connections with their metadata
        for (const connInfo of affectedConnections) {
          const sourceNode = hook.nodeMap.get(connInfo.source);
          const targetNode = hook.nodeMap.get(connInfo.target);
          if (sourceNode && targetNode) {
            if (
              sourceNode.outputs[connInfo.sourceOutput] &&
              targetNode.inputs[connInfo.targetInput]
            ) {
              const connection = new ClassicPreset.Connection(
                sourceNode,
                connInfo.sourceOutput,
                targetNode,
                connInfo.targetInput,
              );
              await hook.editor.addConnection(connection);

              // Restore connection metadata (labels, conditions)
              if (connInfo.connData) {
                hook.connectionDataMap.set(connection.id, connInfo.connData);
              }
            }
          }
        }
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    /**
     * Handles connection added event from server.
     * @param {Object} data - Connection data
     */
    async handleConnectionAdded(data) {
      // Check if this connection already exists locally (user created it)
      const existingConn = hook.editor.getConnections().find(
        (c) =>
          hook.editor.getNode(c.source)?.nodeId === data.source_node_id &&
          c.sourceOutput === data.source_pin &&
          hook.editor.getNode(c.target)?.nodeId === data.target_node_id &&
          c.targetInput === data.target_pin,
      );

      if (existingConn) {
        // Connection already exists locally. Just update the connectionDataMap with server ID.
        hook.connectionDataMap.set(existingConn.id, {
          id: data.id,
          label: data.label || null,
          condition: data.condition || null,
        });
        return;
      }

      // Connection doesn't exist locally (e.g., from collaborator). Add it.
      hook.enterLoadingFromServer();
      try {
        await hook.addConnectionToEditor(data);
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    /**
     * Handles connection removed event from server.
     * @param {Object} data - Data with source_node_id and target_node_id
     */
    async handleConnectionRemoved(data) {
      hook.enterLoadingFromServer();
      try {
        const connections = hook.editor.getConnections();
        for (const conn of connections) {
          const sourceNode = hook.editor.getNode(conn.source);
          const targetNode = hook.editor.getNode(conn.target);

          if (
            sourceNode?.nodeId === data.source_node_id &&
            targetNode?.nodeId === data.target_node_id
          ) {
            hook.connectionDataMap.delete(conn.id);
            await hook.editor.removeConnection(conn.id);
            break;
          }
        }
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    /**
     * Handles connection updated event from server.
     * @param {Object} data - Data with id, label
     */
    handleConnectionUpdated(data) {
      const connId = `conn-${data.id}`;
      hook.connectionDataMap.set(connId, {
        id: data.id,
        label: data.label,
        condition: data.condition,
      });

      const conn = hook.editor.getConnections().find((c) => c.id === connId);
      if (conn) {
        hook.area.update("connection", conn.id);
      }
    },

    /**
     * Cleans up debounce timers.
     */
    destroy() {
      for (const timer of Object.values(hook.debounceTimers)) {
        clearTimeout(timer);
      }
    },
  };
}
