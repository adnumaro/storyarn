/**
 * Editor handlers for node and connection CRUD operations.
 */

import { ClassicPreset } from "rete";
import { FlowNode } from "../flow_node.js";

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
      for (const conn of hook.editor.getConnections()) {
        await hook.editor.removeConnection(conn.id);
      }
      for (const node of hook.editor.getNodes()) {
        await hook.editor.removeNode(node.id);
      }
      hook.nodeMap.clear();
      hook.connectionDataMap.clear();
      await hook.loadFlow(data);
    },

    /**
     * Handles node added event from server.
     * @param {Object} data - Node data
     */
    async handleNodeAdded(data) {
      await hook.addNodeToEditor(data);
    },

    /**
     * Handles node removed event from server.
     * @param {Object} data - Data with node id
     */
    async handleNodeRemoved(data) {
      const node = hook.nodeMap.get(data.id);
      if (node) {
        await hook.editor.removeNode(node.id);
        hook.nodeMap.delete(data.id);
        if (hook.selectedNodeId === data.id) {
          hook.selectedNodeId = null;
        }
      }
    },

    /**
     * Handles node updated event from server.
     * For dialogue nodes with changing responses, rebuilds the entire node.
     * @param {Object} data - Data with id and nodeData
     */
    async handleNodeUpdated(data) {
      const { id, data: nodeData } = data;

      const existingNode = hook.nodeMap.get(id);
      if (!existingNode) {
        return;
      }

      // Check if responses changed (need full rebuild to update outputs)
      const oldResponses = existingNode.nodeData?.responses || [];
      const newResponses = nodeData.responses || [];
      const responsesChanged =
        oldResponses.length !== newResponses.length ||
        oldResponses.some((r, i) => r.id !== newResponses[i]?.id);

      // For dialogue nodes with changing responses, rebuild the node
      if (existingNode.nodeType === "dialogue" && responsesChanged) {
        await this.rebuildDialogueNode(id, existingNode, nodeData);
      } else {
        existingNode.nodeData = nodeData;
        await hook.area.update("node", existingNode.id);
      }
    },

    /**
     * Rebuilds a dialogue node preserving its connections.
     * @param {string|number} id - The database node ID
     * @param {Object} existingNode - The existing Rete node
     * @param {Object} nodeData - The new node data
     */
    async rebuildDialogueNode(id, existingNode, nodeData) {
      const position = await hook.area.getNodePosition(existingNode.id);

      hook.isLoadingFromServer = true;
      const connections = hook.editor.getConnections();
      const affectedConnections = [];

      // Save and remove affected connections
      for (const conn of connections) {
        if (conn.source === existingNode.id || conn.target === existingNode.id) {
          affectedConnections.push({
            source: hook.editor.getNode(conn.source)?.nodeId,
            sourceOutput: conn.sourceOutput,
            target: hook.editor.getNode(conn.target)?.nodeId,
            targetInput: conn.targetInput,
          });
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

      // Force re-render to update visual (speaker name, etc.)
      await hook.area.update("node", newNode.id);

      // Restore connections
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
          }
        }
      }

      hook.isLoadingFromServer = false;
    },

    /**
     * Handles connection added event from server.
     * @param {Object} data - Connection data
     */
    async handleConnectionAdded(data) {
      hook.isLoadingFromServer = true;
      try {
        await hook.addConnectionToEditor(data);
      } finally {
        hook.isLoadingFromServer = false;
      }
    },

    /**
     * Handles connection removed event from server.
     * @param {Object} data - Data with source_node_id and target_node_id
     */
    async handleConnectionRemoved(data) {
      hook.isLoadingFromServer = true;
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
        hook.isLoadingFromServer = false;
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
