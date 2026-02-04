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

// Import handlers
import {
  createCursorHandler,
  createEditorHandlers,
  createKeyboardHandler,
  createLockHandler,
} from "./flow_canvas/handlers/index.js";

export const FlowCanvas = {
  mounted() {
    this.initEditor();
  },

  async initEditor() {
    const container = this.el;
    const flowData = JSON.parse(container.dataset.flow || "{}");
    this.pagesMap = JSON.parse(container.dataset.pages || "{}");

    // Collaboration data
    this.currentUserId = Number.parseInt(container.dataset.userId, 10);
    this.currentUserColor = container.dataset.userColor || "#3b82f6";

    // Initialize handlers
    this.cursorHandler = createCursorHandler(this);
    this.lockHandler = createLockHandler(this);
    this.editorHandlers = createEditorHandlers(this);

    this.cursorHandler.init();
    this.lockHandler.init();
    this.editorHandlers.init();

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
            // Create a new object with spread to ensure Lit detects changes
            const nodeData = {
              ...context.payload,
              nodeData: { ...context.payload.nodeData },
              _updateTs: Date.now(), // Force new reference for re-renders
            };
            return ({ emit }) => html`
              <storyarn-node
                .data=${nodeData}
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
    this.isLoadingFromServer = false;

    // Load initial flow data
    if (flowData.nodes) {
      await this.loadFlow(flowData);
    }

    // Set up event handlers
    this.setupEventHandlers();

    // Initialize keyboard handler after editor is ready
    this.keyboardHandler = createKeyboardHandler(this, this.lockHandler);
    this.keyboardHandler.init();

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
    this.lastNodeClickTime = 0;
    this.lastClickedNodeId = null;

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
          this.editorHandlers.debounceNodeMoved(node.nodeId, context.data.position);
        }
      }
      return context;
    });

    // Node selection with double-click detection
    this.area.addPipe((context) => {
      if (context.type === "nodepicked") {
        const node = this.editor.getNode(context.data.id);
        if (node?.nodeId) {
          const now = Date.now();
          const isDoubleClick =
            this.lastClickedNodeId === node.nodeId && now - this.lastNodeClickTime < 300;

          this.lastNodeClickTime = now;
          this.lastClickedNodeId = node.nodeId;
          this.selectedNodeId = node.nodeId;

          if (isDoubleClick && node.nodeType === "dialogue") {
            // Double-click on dialogue node -> screenplay mode
            this.pushEvent("node_double_clicked", { id: node.nodeId });
          } else {
            // Single click -> sidebar mode
            this.pushEvent("node_selected", { id: node.nodeId });
          }
        }
      }
      return context;
    });

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

    // Handle server events - Editor
    this.handleEvent("flow_updated", (data) => this.editorHandlers.handleFlowUpdated(data));
    this.handleEvent("node_added", (data) => this.editorHandlers.handleNodeAdded(data));
    this.handleEvent("node_removed", (data) => this.editorHandlers.handleNodeRemoved(data));
    this.handleEvent("node_updated", (data) => this.editorHandlers.handleNodeUpdated(data));
    this.handleEvent("connection_added", (data) => this.editorHandlers.handleConnectionAdded(data));
    this.handleEvent("connection_removed", (data) =>
      this.editorHandlers.handleConnectionRemoved(data),
    );
    this.handleEvent("connection_updated", (data) =>
      this.editorHandlers.handleConnectionUpdated(data),
    );
    this.handleEvent("deselect_connection", () => {
      this.selectedConnectionId = null;
    });

    // Handle server events - Collaboration
    this.handleEvent("cursor_update", (data) => this.cursorHandler.handleCursorUpdate(data));
    this.handleEvent("cursor_leave", (data) => this.cursorHandler.handleCursorLeave(data));
    this.handleEvent("locks_updated", (data) => this.lockHandler.handleLocksUpdated(data));
  },

  destroyed() {
    // Cleanup handlers
    this.cursorHandler?.destroy();
    this.keyboardHandler?.destroy();
    this.editorHandlers?.destroy();

    // Cleanup minimap
    if (this.minimap?.element) {
      this.minimap.element.remove();
    }

    // Cleanup area
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
