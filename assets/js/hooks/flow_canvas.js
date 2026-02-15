/**
 * FlowCanvas - Phoenix LiveView Hook for the narrative flow editor.
 *
 * Orchestrator: delegates plugin setup to setup.js, event wiring to event_bindings.js,
 * and CRUD operations to handler modules.
 */

import { ClassicPreset } from "rete";

import "../flow_canvas/components/index.js";
import { FlowNode } from "../flow_canvas/flow_node.js";
import { createPlugins, finalizeSetup } from "../flow_canvas/setup.js";
import { setupEventHandlers } from "../flow_canvas/event_bindings.js";
import {
  createCursorHandler,
  createDebugHandler,
  createEditorHandlers,
  createKeyboardHandler,
  createLockHandler,
  createNavigationHandler,
} from "../flow_canvas/handlers/index.js";
import { createLodController } from "../flow_canvas/lod_controller.js";

export const FlowCanvas = {
  mounted() {
    this.initEditor();
  },

  get isLoadingFromServer() {
    return this._loadingFromServerCount > 0;
  },

  enterLoadingFromServer() {
    this._loadingFromServerCount++;
  },

  exitLoadingFromServer() {
    this._loadingFromServerCount = Math.max(0, this._loadingFromServerCount - 1);
  },

  async initEditor() {
    const container = this.el;
    const flowData = JSON.parse(container.dataset.flow || "{}");
    this.sheetsMap = JSON.parse(container.dataset.sheets || "{}");

    // Collaboration data
    this.currentUserId = Number.parseInt(container.dataset.userId, 10);
    this.currentUserColor = container.dataset.userColor || "#3b82f6";

    // Initialize handlers
    this.cursorHandler = createCursorHandler(this);
    this.lockHandler = createLockHandler(this);
    this.editorHandlers = createEditorHandlers(this);

    this.navigationHandler = createNavigationHandler(this);
    this.debugHandler = createDebugHandler(this);

    this.cursorHandler.init();
    this.lockHandler.init();
    this.editorHandlers.init();

    // Create and configure plugins (socket deferral pipe reads these flags)
    this.connectionDataMap = new Map();
    this.nodeMap = new Map();
    this._loadingFromServerCount = 0;
    this._deferSocketCalc = false;
    this._deferredSockets = [];

    const plugins = createPlugins(container, this);
    this.editor = plugins.editor;
    this.area = plugins.area;
    this.connection = plugins.connection;
    this.minimap = plugins.minimap;
    this.render = plugins.render;

    // Start in simplified LOD so nodes render ~12 elements instead of ~50.
    // zoomAt (100ms after finalizeSetup) fires a "zoomed" event that triggers
    // a batched transition to full LOD if the zoom level warrants it.
    this.currentLod = "simplified";
    this.lodController = createLodController(this, "simplified");

    // Load initial flow data in 3 phases to minimize forced reflows:
    //   1. Add nodes  — socket positions deferred (no reflows)
    //   2. Flush sockets — no connections yet (ONE reflow, no DOM write-backs)
    //   3. Add connections — positions cached (no reflows)
    this.hubsMap = {};
    if (flowData.nodes) {
      this._deferSocketCalc = true;
      this.enterLoadingFromServer();

      for (const nodeData of flowData.nodes) {
        await this.addNodeToEditor(nodeData);
      }

      this._deferSocketCalc = false;
      await this.flushDeferredSockets();

      for (const connData of flowData.connections || []) {
        await this.addConnectionToEditor(connData);
      }

      this.exitLoadingFromServer();
    }


    // Register minimap after all nodes/connections are loaded
    if (this.minimap) {
      this.area.use(this.minimap);
    }

    // Set up event handlers
    setupEventHandlers(this);

    // Wire LOD zoom watching (after setupEventHandlers, before finalizeSetup)
    this.area.addPipe((context) => {
      if (context.type === "zoomed") {
        this.lodController.onZoom();
      }
      return context;
    });

    // Initialize keyboard handler after editor is ready
    this.keyboardHandler = createKeyboardHandler(this, this.lockHandler);
    this.keyboardHandler.init();

    // Enable zoom, pan, fit view
    await finalizeSetup(this.area, this.editor, flowData.nodes?.length > 0);

    // Single rebuild AFTER area is fully ready
    if (flowData.nodes?.length > 0) {
      await this.rebuildHubsMap();
    }

    // Canvas is ready — hide the root layout loading overlay
    document.getElementById("page-loader")?.classList.add("hidden");
  },

  async flushDeferredSockets() {
    const deferred = this._deferredSockets;
    this._deferredSockets = [];

    for (const ctx of deferred) {
      await this.area.emit(ctx);
    }
  },

  async loadFlow(flowData) {
    this.enterLoadingFromServer();
    try {
      for (const nodeData of flowData.nodes || []) {
        await this.addNodeToEditor(nodeData);
      }
      for (const connData of flowData.connections || []) {
        await this.addConnectionToEditor(connData);
      }
    } finally {
      this.exitLoadingFromServer();
    }
  },

  async addNodeToEditor(nodeData) {
    const node = new FlowNode(nodeData.type, nodeData.id, nodeData.data);
    node.id = `node-${nodeData.id}`;

    await this.editor.addNode(node);

    const x = nodeData.position?.x || 0;
    const y = nodeData.position?.y || 0;

    if (this._deferSocketCalc) {
      // Bulk load: set position directly on the view, bypassing area pipe chain.
      // Skips nodetranslated events (minimap, position watcher, socket invalidation)
      // which are all wasted during initial load.
      const view = this.area.nodeViews.get(node.id);
      if (view) view.translate(x, y);
    } else {
      await this.area.translate(node.id, { x, y });
    }

    this.nodeMap.set(nodeData.id, node);
    return node;
  },

  async addConnectionToEditor(connData) {
    const sourceNode = this.nodeMap.get(connData.source_node_id);
    const targetNode = this.nodeMap.get(connData.target_node_id);

    if (!sourceNode || !targetNode) return;

    // Skip connections referencing pins that no longer exist on the node
    // (e.g., a deleted dialogue response whose connection wasn't cleaned up)
    if (!sourceNode.outputs[connData.source_pin]) {
      console.warn(
        `Skipping connection ${connData.id}: source pin "${connData.source_pin}" not found on node ${connData.source_node_id}`,
      );
      return;
    }
    if (!targetNode.inputs[connData.target_pin]) {
      console.warn(
        `Skipping connection ${connData.id}: target pin "${connData.target_pin}" not found on node ${connData.target_node_id}`,
      );
      return;
    }

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

  async rebuildHubsMap() {
    const map = {};
    for (const [, node] of this.nodeMap) {
      if (node.nodeType === "hub" && node.nodeData?.hub_id) {
        map[node.nodeData.hub_id] = {
          color_hex: node.nodeData.color_hex || null,
          label: node.nodeData.label || "",
          jumpCount: 0,
        };
      }
    }
    for (const [, node] of this.nodeMap) {
      if (node.nodeType === "jump" && node.nodeData?.target_hub_id) {
        const entry = map[node.nodeData.target_hub_id];
        if (entry) entry.jumpCount++;
      }
    }
    this.hubsMap = map;

    // Rete's area.update only propagates .data/.emit to Lit components,
    // not custom props like .hubsMap. Set it directly on DOM elements.
    for (const el of this.el.querySelectorAll("storyarn-node")) {
      el.hubsMap = map;
    }

    // Also trigger area.update for layout recalculation
    const ts = Date.now();
    for (const [, node] of this.nodeMap) {
      if (node.nodeType === "hub" || node.nodeType === "jump") {
        node._updateTs = ts;
        await this.area.update("node", node.id);
      }
    }
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
    this.lodController?.destroy();
    this.cursorHandler?.destroy();
    this.keyboardHandler?.destroy();
    this.editorHandlers?.destroy();
    this.navigationHandler?.destroy();
    this.debugHandler?.destroy();

    if (this.minimap?.element) {
      this.minimap.element.remove();
    }

    if (this.area) {
      this.area.destroy();
    }

    // Ensure overlay is hidden when leaving the flow page
    document.getElementById("page-loader")?.classList.add("hidden");
  },
};
