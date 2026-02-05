/**
 * FlowCanvas - Phoenix LiveView Hook for the narrative flow editor.
 *
 * Orchestrator: delegates plugin setup to setup.js, event wiring to event_bindings.js,
 * and CRUD operations to handler modules.
 */

import { ClassicPreset } from "rete";

import "./flow_canvas/components/index.js";
import { FlowNode } from "./flow_canvas/flow_node.js";
import { createPlugins, finalizeSetup } from "./flow_canvas/setup.js";
import { setupEventHandlers } from "./flow_canvas/event_bindings.js";
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

    // Create and configure plugins
    this.connectionDataMap = new Map();
    this.nodeMap = new Map();
    this.isLoadingFromServer = false;

    const plugins = createPlugins(container, this);
    this.editor = plugins.editor;
    this.area = plugins.area;
    this.connection = plugins.connection;
    this.minimap = plugins.minimap;
    this.render = plugins.render;

    // Load initial flow data
    if (flowData.nodes) {
      await this.loadFlow(flowData);
    }

    // Set up event handlers
    setupEventHandlers(this);

    // Initialize keyboard handler after editor is ready
    this.keyboardHandler = createKeyboardHandler(this, this.lockHandler);
    this.keyboardHandler.init();

    // Enable zoom, pan, fit view
    await finalizeSetup(this.area, this.editor, flowData.nodes?.length > 0);
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

  disconnected() {
    this.cursorHandler?.pause();
    this.el.classList.add("opacity-50", "pointer-events-none");
  },

  reconnected() {
    this.el.classList.remove("opacity-50", "pointer-events-none");
    this.cursorHandler?.resume();
    this.pushEvent("request_flow_refresh", {});
  },

  destroyed() {
    this.cursorHandler?.destroy();
    this.keyboardHandler?.destroy();
    this.editorHandlers?.destroy();

    if (this.minimap?.element) {
      this.minimap.element.remove();
    }

    if (this.area) {
      this.area.destroy();
    }
  },
};
