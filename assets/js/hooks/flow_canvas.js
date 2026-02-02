/**
 * FlowCanvas - Phoenix LiveView Hook for the narrative flow editor.
 *
 * Uses Rete.js with custom LitElement components for rendering.
 */

import { LitPlugin, Presets as LitPresets } from "@retejs/lit-plugin";
import { html } from "lit";
import { ClassicPreset, NodeEditor } from "rete";
import { AreaExtensions, AreaPlugin } from "rete-area-plugin";
import { ConnectionPlugin, Presets as ConnectionPresets } from "rete-connection-plugin";
import { MinimapPlugin } from "rete-minimap-plugin";

// Import our custom components and config
import "./flow_canvas/components/index.js";
import { FlowNode } from "./flow_canvas/flow_node.js";

export const FlowCanvas = {
  mounted() {
    this.initEditor();
  },

  async initEditor() {
    const container = this.el;
    const flowData = JSON.parse(container.dataset.flow || "{}");
    this.pagesMap = JSON.parse(container.dataset.pages || "{}");

    // Collaboration data
    this.nodeLocks = JSON.parse(container.dataset.locks || "{}");
    this.currentUserId = Number.parseInt(container.dataset.userId, 10);
    this.currentUserColor = container.dataset.userColor || "#3b82f6";
    this.remoteCursors = new Map();

    // Create cursor overlay container
    this.cursorOverlay = document.createElement("div");
    this.cursorOverlay.className = "cursor-overlay";
    this.cursorOverlay.style.cssText =
      "position: absolute; inset: 0; pointer-events: none; z-index: 100;";
    container.appendChild(this.cursorOverlay);

    // Create the editor
    this.editor = new NodeEditor();
    this.area = new AreaPlugin(container);
    this.connection = new ConnectionPlugin();
    this.minimap = new MinimapPlugin();

    // Create render plugin with Lit
    this.render = new LitPlugin();

    // Configure connection plugin
    this.connection.addPreset(ConnectionPresets.classic.setup());

    // Track connection data for labels
    this.connectionDataMap = new Map();

    // Store reference for use in customizers
    const self = this;

    // Configure Lit render plugin with custom components
    this.render.addPreset(
      LitPresets.classic.setup({
        customize: {
          node(context) {
            return ({ emit }) => html`
              <storyarn-node
                .data=${context.payload}
                .emit=${emit}
                .pagesMap=${self.pagesMap}
              ></storyarn-node>
            `;
          },
          socket(context) {
            return () => html`
              <storyarn-socket .data=${context.payload}></storyarn-socket>
            `;
          },
          connection: (context) => {
            const conn = context.payload;
            return ({ path }) => {
              const connData = this.connectionDataMap.get(conn.id);
              return html`
                <storyarn-connection
                  .path=${path}
                  .data=${connData}
                  .selected=${this.selectedConnectionId === connData?.id}
                ></storyarn-connection>
              `;
            };
          },
        },
      }),
    );

    // Register plugins
    this.editor.use(this.area);
    this.area.use(this.connection);
    this.area.use(this.render);
    this.area.use(this.minimap);

    // Track nodes by database ID
    this.nodeMap = new Map();
    this.debounceTimers = {};
    this.isLoadingFromServer = false;

    // Load initial flow data
    if (flowData.nodes) {
      await this.loadFlow(flowData);
    }

    // Set up event handlers
    this.setupEventHandlers();

    // Enable zoom and pan
    AreaExtensions.selectableNodes(this.area, AreaExtensions.selector(), {
      accumulating: AreaExtensions.accumulateOnCtrl(),
    });

    // Fit view to content if there are nodes
    if (flowData.nodes?.length > 0) {
      setTimeout(async () => {
        await AreaExtensions.zoomAt(this.area, this.editor.getNodes());
      }, 100);
    }
  },

  async loadFlow(flowData) {
    this.isLoadingFromServer = true;
    try {
      for (const nodeData of flowData.nodes || []) {
        await this.addNodeToEditor(nodeData);
      }
      for (const connData of flowData.connections || []) {
        await this.addConnectionToEditor(connData);
      }
    } finally {
      this.isLoadingFromServer = false;
    }
  },

  async addNodeToEditor(nodeData) {
    const node = new FlowNode(nodeData.type, nodeData.id, nodeData.data);
    node.id = `node-${nodeData.id}`;

    await this.editor.addNode(node);
    await this.area.translate(node.id, {
      x: nodeData.position?.x || 0,
      y: nodeData.position?.y || 0,
    });

    this.nodeMap.set(nodeData.id, node);
    return node;
  },

  async addConnectionToEditor(connData) {
    const sourceNode = this.nodeMap.get(connData.source_node_id);
    const targetNode = this.nodeMap.get(connData.target_node_id);

    if (!sourceNode || !targetNode) return;

    const connection = new ClassicPreset.Connection(
      sourceNode,
      connData.source_pin,
      targetNode,
      connData.target_pin,
    );
    connection.id = `conn-${connData.id}`;

    this.connectionDataMap.set(connection.id, {
      id: connData.id,
      label: connData.label,
      condition: connData.condition,
    });

    await this.editor.addConnection(connection);
    return connection;
  },

  setupEventHandlers() {
    this.selectedNodeId = null;
    this.selectedConnectionId = null;

    // Listen for connection double-clicks
    this.el.addEventListener("connection-dblclick", (e) => {
      const { connectionId } = e.detail;
      if (connectionId) {
        this.selectedConnectionId = connectionId;
        this.pushEvent("connection_selected", { id: connectionId });
      }
    });

    // Node position changes (drag)
    this.area.addPipe((context) => {
      if (context.type === "nodetranslated") {
        const node = this.editor.getNode(context.data.id);
        if (node?.nodeId) {
          this.debounceNodeMoved(node.nodeId, context.data.position);
        }
      }
      return context;
    });

    // Node selection
    this.area.addPipe((context) => {
      if (context.type === "nodepicked") {
        const node = this.editor.getNode(context.data.id);
        if (node?.nodeId) {
          this.selectedNodeId = node.nodeId;
          this.pushEvent("node_selected", { id: node.nodeId });
        }
      }
      return context;
    });

    // Keyboard shortcuts
    this.keyboardHandler = (e) => this.handleKeyboard(e);
    document.addEventListener("keydown", this.keyboardHandler);

    // Connection created
    this.editor.addPipe((context) => {
      if (context.type === "connectioncreate" && !this.isLoadingFromServer) {
        const conn = context.data;
        const sourceNode = this.editor.getNode(conn.source);
        const targetNode = this.editor.getNode(conn.target);

        if (sourceNode?.nodeId && targetNode?.nodeId) {
          this.pushEvent("connection_created", {
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
    this.editor.addPipe((context) => {
      if (context.type === "connectionremove" && !this.isLoadingFromServer) {
        const conn = context.data;
        const sourceNode = this.editor.getNode(conn.source);
        const targetNode = this.editor.getNode(conn.target);

        if (sourceNode?.nodeId && targetNode?.nodeId) {
          this.pushEvent("connection_deleted", {
            source_node_id: sourceNode.nodeId,
            target_node_id: targetNode.nodeId,
          });
        }
      }
      return context;
    });

    // Cursor tracking
    this.lastCursorSend = 0;
    this.cursorThrottleMs = 50;
    this.mouseMoveHandler = (e) => this.handleMouseMove(e);
    this.el.addEventListener("mousemove", this.mouseMoveHandler);

    // Handle server events
    this.handleEvent("flow_updated", (data) => this.handleFlowUpdated(data));
    this.handleEvent("node_added", (data) => this.handleNodeAdded(data));
    this.handleEvent("node_removed", (data) => this.handleNodeRemoved(data));
    this.handleEvent("node_updated", (data) => this.handleNodeUpdated(data));
    this.handleEvent("connection_added", (data) => this.handleConnectionAdded(data));
    this.handleEvent("connection_removed", (data) => this.handleConnectionRemoved(data));
    this.handleEvent("connection_updated", (data) => this.handleConnectionUpdated(data));
    this.handleEvent("deselect_connection", () => {
      this.selectedConnectionId = null;
    });

    // Collaboration events
    this.handleEvent("cursor_update", (data) => this.handleCursorUpdate(data));
    this.handleEvent("cursor_leave", (data) => this.handleCursorLeave(data));
    this.handleEvent("locks_updated", (data) => this.handleLocksUpdated(data));
  },

  // =============================================================================
  // Cursor & Collaboration Handlers
  // =============================================================================

  handleMouseMove(e) {
    const now = Date.now();
    if (now - this.lastCursorSend < this.cursorThrottleMs) return;
    this.lastCursorSend = now;

    const rect = this.el.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    const transform = this.area.area.transform;
    const canvasX = (x - transform.x) / transform.k;
    const canvasY = (y - transform.y) / transform.k;

    this.pushEvent("cursor_moved", { x: canvasX, y: canvasY });
  },

  handleCursorUpdate(data) {
    if (data.user_id === this.currentUserId) return;

    let cursorEl = this.remoteCursors.get(data.user_id);
    if (!cursorEl) {
      cursorEl = this.createRemoteCursor(data);
      this.remoteCursors.set(data.user_id, cursorEl);
      this.cursorOverlay.appendChild(cursorEl);
    }

    const transform = this.area.area.transform;
    const screenX = data.x * transform.k + transform.x;
    const screenY = data.y * transform.k + transform.y;

    cursorEl.style.transform = `translate(${screenX}px, ${screenY}px)`;
    cursorEl.style.opacity = "1";

    if (cursorEl._fadeTimer) clearTimeout(cursorEl._fadeTimer);
    cursorEl._fadeTimer = setTimeout(() => {
      cursorEl.style.opacity = "0.3";
    }, 3000);
  },

  handleCursorLeave(data) {
    const cursorEl = this.remoteCursors.get(data.user_id);
    if (cursorEl) {
      cursorEl.remove();
      this.remoteCursors.delete(data.user_id);
    }
  },

  createRemoteCursor(data) {
    const cursor = document.createElement("div");
    cursor.className = "remote-cursor";
    cursor.style.cssText = `
      position: absolute;
      top: 0;
      left: 0;
      pointer-events: none;
      transition: transform 0.05s linear, opacity 0.3s ease;
      z-index: 100;
    `;

    const emailName = data.user_email?.split("@")[0] || "User";

    cursor.innerHTML = `
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" style="filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));">
        <path d="M5.5 3.21V20.8c0 .45.54.67.85.35l4.86-4.86a.5.5 0 0 1 .35-.15h6.87c.48 0 .72-.58.38-.92L6.35 2.86a.5.5 0 0 0-.85.35Z" fill="${data.user_color}" stroke="white" stroke-width="1.5"/>
      </svg>
      <span style="
        position: absolute;
        top: 20px;
        left: 12px;
        background: ${data.user_color};
        color: white;
        font-size: 10px;
        padding: 2px 6px;
        border-radius: 4px;
        white-space: nowrap;
        font-family: system-ui, sans-serif;
      ">${emailName}</span>
    `;

    return cursor;
  },

  handleLocksUpdated(data) {
    this.nodeLocks = data.locks || {};
    this.updateLockIndicators();
  },

  updateLockIndicators() {
    for (const [nodeId, node] of this.nodeMap.entries()) {
      const lockInfo = this.nodeLocks[nodeId];
      const nodeEl = this.area.nodeViews.get(node.id)?.element;
      if (!nodeEl) continue;

      const existingLock = nodeEl.querySelector(".node-lock-indicator");
      if (existingLock) existingLock.remove();

      if (lockInfo && lockInfo.user_id !== this.currentUserId) {
        const lockEl = document.createElement("div");
        lockEl.className = "node-lock-indicator";
        const emailName = lockInfo.user_email?.split("@")[0] || "User";
        lockEl.innerHTML = `
          <svg width="12" height="12" viewBox="0 0 20 20" fill="${lockInfo.user_color}">
            <path fill-rule="evenodd" d="M10 1a4.5 4.5 0 0 0-4.5 4.5V9H5a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-.5V5.5A4.5 4.5 0 0 0 10 1Zm3 8V5.5a3 3 0 1 0-6 0V9h6Z" clip-rule="evenodd"/>
          </svg>
          <span>${emailName}</span>
        `;
        lockEl.style.cssText = `
          position: absolute;
          top: -8px;
          right: -8px;
          display: flex;
          align-items: center;
          gap: 4px;
          padding: 2px 6px;
          background: white;
          border: 1px solid ${lockInfo.user_color};
          border-radius: 12px;
          font-size: 10px;
          color: ${lockInfo.user_color};
          font-family: system-ui, sans-serif;
          z-index: 10;
          box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        `;
        nodeEl.style.position = "relative";
        nodeEl.appendChild(lockEl);
      }
    }
  },

  isNodeLocked(nodeId) {
    const lockInfo = this.nodeLocks[nodeId];
    return lockInfo && lockInfo.user_id !== this.currentUserId;
  },

  // =============================================================================
  // Node & Connection Handlers
  // =============================================================================

  debounceNodeMoved(nodeId, position) {
    if (this.debounceTimers[nodeId]) {
      clearTimeout(this.debounceTimers[nodeId]);
    }

    this.debounceTimers[nodeId] = setTimeout(() => {
      this.pushEvent("node_moved", {
        id: nodeId,
        position_x: position.x,
        position_y: position.y,
      });
      delete this.debounceTimers[nodeId];
    }, 300);
  },

  async handleFlowUpdated(data) {
    for (const conn of this.editor.getConnections()) {
      await this.editor.removeConnection(conn.id);
    }
    for (const node of this.editor.getNodes()) {
      await this.editor.removeNode(node.id);
    }
    this.nodeMap.clear();
    this.connectionDataMap.clear();
    await this.loadFlow(data);
  },

  async handleNodeAdded(data) {
    await this.addNodeToEditor(data);
  },

  async handleNodeRemoved(data) {
    const node = this.nodeMap.get(data.id);
    if (node) {
      await this.editor.removeNode(node.id);
      this.nodeMap.delete(data.id);
      if (this.selectedNodeId === data.id) {
        this.selectedNodeId = null;
      }
    }
  },

  async handleNodeUpdated(data) {
    const { id, data: nodeData } = data;
    const existingNode = this.nodeMap.get(id);
    if (!existingNode) return;

    // For dialogue nodes with changing responses, rebuild the node
    if (existingNode.nodeType === "dialogue") {
      const position = await this.area.getNodePosition(existingNode.id);

      this.isLoadingFromServer = true;
      const connections = this.editor.getConnections();
      const affectedConnections = [];
      for (const conn of connections) {
        if (conn.source === existingNode.id || conn.target === existingNode.id) {
          affectedConnections.push({
            source: this.editor.getNode(conn.source)?.nodeId,
            sourceOutput: conn.sourceOutput,
            target: this.editor.getNode(conn.target)?.nodeId,
            targetInput: conn.targetInput,
          });
          await this.editor.removeConnection(conn.id);
        }
      }

      await this.editor.removeNode(existingNode.id);
      this.nodeMap.delete(id);

      const newNode = new FlowNode(existingNode.nodeType, id, nodeData);
      newNode.id = `node-${id}`;

      await this.editor.addNode(newNode);
      await this.area.translate(newNode.id, position);
      this.nodeMap.set(id, newNode);

      for (const connInfo of affectedConnections) {
        const sourceNode = this.nodeMap.get(connInfo.source);
        const targetNode = this.nodeMap.get(connInfo.target);
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
            await this.editor.addConnection(connection);
          }
        }
      }

      this.isLoadingFromServer = false;
    } else {
      existingNode.nodeData = nodeData;
      await this.area.update("node", existingNode.id);
    }
  },

  async handleConnectionAdded(data) {
    this.isLoadingFromServer = true;
    try {
      await this.addConnectionToEditor(data);
    } finally {
      this.isLoadingFromServer = false;
    }
  },

  async handleConnectionRemoved(data) {
    this.isLoadingFromServer = true;
    try {
      const connections = this.editor.getConnections();
      for (const conn of connections) {
        const sourceNode = this.editor.getNode(conn.source);
        const targetNode = this.editor.getNode(conn.target);

        if (
          sourceNode?.nodeId === data.source_node_id &&
          targetNode?.nodeId === data.target_node_id
        ) {
          this.connectionDataMap.delete(conn.id);
          await this.editor.removeConnection(conn.id);
          break;
        }
      }
    } finally {
      this.isLoadingFromServer = false;
    }
  },

  handleConnectionUpdated(data) {
    const connId = `conn-${data.id}`;
    this.connectionDataMap.set(connId, {
      id: data.id,
      label: data.label,
      condition: data.condition,
    });

    const conn = this.editor.getConnections().find((c) => c.id === connId);
    if (conn) {
      this.area.update("connection", conn.id);
    }
  },

  // =============================================================================
  // Keyboard Handler
  // =============================================================================

  handleKeyboard(e) {
    if (
      e.target.tagName === "INPUT" ||
      e.target.tagName === "TEXTAREA" ||
      e.target.isContentEditable
    ) {
      return;
    }

    // Delete/Backspace - delete selected node
    if ((e.key === "Delete" || e.key === "Backspace") && this.selectedNodeId) {
      e.preventDefault();
      if (this.isNodeLocked(this.selectedNodeId)) return;
      this.pushEvent("delete_node", { id: this.selectedNodeId });
      this.selectedNodeId = null;
      return;
    }

    // Ctrl+D / Cmd+D - duplicate selected node
    if ((e.ctrlKey || e.metaKey) && e.key === "d" && this.selectedNodeId) {
      e.preventDefault();
      this.pushEvent("duplicate_node", { id: this.selectedNodeId });
      return;
    }

    // Escape - deselect node
    if (e.key === "Escape" && this.selectedNodeId) {
      e.preventDefault();
      this.pushEvent("deselect_node", {});
      this.selectedNodeId = null;
      return;
    }
  },

  // =============================================================================
  // Cleanup
  // =============================================================================

  destroyed() {
    if (this.keyboardHandler) {
      document.removeEventListener("keydown", this.keyboardHandler);
    }

    if (this.mouseMoveHandler) {
      this.el.removeEventListener("mousemove", this.mouseMoveHandler);
    }

    for (const timer of Object.values(this.debounceTimers)) {
      clearTimeout(timer);
    }

    for (const cursor of this.remoteCursors.values()) {
      if (cursor._fadeTimer) clearTimeout(cursor._fadeTimer);
    }

    if (this.cursorOverlay) {
      this.cursorOverlay.remove();
    }

    if (this.minimap?.element) {
      this.minimap.element.remove();
    }

    if (this.area) {
      this.area.destroy();
    }
  },
};

// =============================================================================
// Global Styles
// =============================================================================

const reteStyles = document.createElement("style");
reteStyles.textContent = `
  /* Canvas background with subtle dot grid */
  #flow-canvas {
    background-color: oklch(var(--b2, 0.2 0 0));
    background-image:
      radial-gradient(circle at center, oklch(var(--bc, 0.8 0 0) / 0.08) 1.5px, transparent 1.5px);
    background-size: 24px 24px;
  }

  /* Minimap styling */
  .rete-minimap {
    position: absolute;
    right: 16px;
    bottom: 16px;
    width: 180px;
    height: 120px;
    background: oklch(var(--b1, 0.25 0 0) / 0.9);
    border: 1px solid oklch(var(--bc, 0.8 0 0) / 0.2);
    border-radius: 8px;
    box-shadow: 0 4px 12px rgb(0 0 0 / 0.15);
    overflow: hidden;
    z-index: 10;
    backdrop-filter: blur(8px);
  }

  .rete-minimap .mini-node {
    border-radius: 2px;
    opacity: 0.8;
  }

  .rete-minimap .mini-viewport {
    border: 2px solid oklch(var(--p, 0.6 0.2 250));
    background: oklch(var(--p, 0.6 0.2 250) / 0.1);
    border-radius: 3px;
  }
`;
document.head.appendChild(reteStyles);
