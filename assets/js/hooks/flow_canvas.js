/**
 * FlowCanvas - Phoenix LiveView Hook for the narrative flow editor.
 *
 * Orchestrator: delegates plugin setup to setup.js, event wiring to event_bindings.js,
 * and CRUD operations to handler modules.
 */

import { ClassicPreset } from "rete";

import "../flow_canvas/components/index.js";
import { setupEventHandlers } from "../flow_canvas/event_bindings.js";
import { createFlowFloatingToolbar } from "../flow_canvas/floating_toolbar.js";
import { FlowNode } from "../flow_canvas/flow_node.js";
import {
  createCursorHandler,
  createDebugHandler,
  createEditorHandlers,
  createKeyboardHandler,
  createLockHandler,
  createNavigationHandler,
} from "../flow_canvas/handlers/index.js";
import { buildBatchPositions } from "../flow_canvas/history_preset.js";
import { createLodController } from "../flow_canvas/lod_controller.js";
import { createPlugins, finalizeSetup } from "../flow_canvas/setup.js";

export const FlowCanvas = {
  mounted() {
    // Define isLoadingFromServer as a live getter on the instance.
    // LiveView's Object.assign copies getters as static values, so we must
    // re-define it here to ensure it reads _loadingFromServerCount dynamically.
    Object.defineProperty(this, "isLoadingFromServer", {
      get() {
        return this._loadingFromServerCount > 0;
      },
      configurable: true,
    });

    this.initEditor();
  },

  enterLoadingFromServer() {
    this._loadingFromServerCount++;
  },

  exitLoadingFromServer() {
    this._loadingFromServerCount = Math.max(0, this._loadingFromServerCount - 1);
  },

  /**
   * Sync the Rete area container size with the actual rendered node dimensions.
   * Rete sets explicit width/height from FlowNode defaults, but dynamic content
   * (images, long text) can make the node taller. Without resizing, connection
   * endpoints won't align with socket positions.
   */
  async syncNodeSize(nodeId) {
    const view = this.area.nodeViews.get(nodeId);
    if (!view) return;
    const el = view.element.querySelector("storyarn-node");
    if (!el) return;

    // Wait for Lit to finish rendering the shadow DOM
    if (el.updateComplete) await el.updateComplete;

    const nodeEl = el.shadowRoot?.querySelector(".node");
    if (!nodeEl) return;
    const w = nodeEl.offsetWidth;
    const h = nodeEl.offsetHeight;
    if (w > 0 && h > 0) {
      await this.area.resize(nodeId, w, h);
    }
  },

  /** Sync sizes for all nodes in the editor. */
  async syncAllNodeSizes() {
    // Wait one frame for all Lit elements to finish rendering
    await new Promise((r) => requestAnimationFrame(r));
    for (const [nodeId] of this.area.nodeViews) {
      await this.syncNodeSize(nodeId);
    }
  },

  /**
   * Force recalculation of ALL socket positions (both input and output).
   * Rete's noderesized event only recalculates OUTPUT sockets; this method
   * replays cached socket rendered events so getElementCenter() runs again
   * with the final DOM layout, fixing stale input socket positions.
   */
  async recalculateAllSockets() {
    const events = this._socketRenderedEvents;
    if (!events || events.length === 0) return;
    this._socketRenderedEvents = [];
    this._isRecalculatingSockets = true;
    // Wait for DOM to be fully laid out
    await new Promise((r) => requestAnimationFrame(r));
    for (const ctx of events) {
      await this.area.emit(ctx);
    }
    this._isRecalculatingSockets = false;
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
    this.history = plugins.history;
    this.arrange = plugins.arrange;
    this.minimap = plugins.minimap;
    this.render = plugins.render;

    // Choose initial LOD based on node count. For small flows (< 50 nodes),
    // start in full LOD to avoid an unnecessary simplified→full transition
    // that can leave socket positions stale. For large flows, start simplified
    // for faster initial paint; zoomAt triggers the transition to full later.
    const nodeCount = flowData.nodes?.length || 0;
    const initialLod = nodeCount >= 50 ? "simplified" : "full";
    this.currentLod = initialLod;
    this.lodController = createLodController(this, initialLod);

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

    // Register history and minimap after all nodes/connections are loaded
    // to avoid recording bulk-load operations in undo history.
    if (this.history) {
      this.area.use(this.history);
    }
    if (this.minimap) {
      this.area.use(this.minimap);
    }

    // Set up event handlers
    setupEventHandlers(this);

    // Floating toolbar
    this.floatingToolbar = createFlowFloatingToolbar(this);
    // Expose floatingToolbar on parent for the FlowFloatingToolbar hook
    this.el.parentElement.__floatingToolbar = this.floatingToolbar;

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

    // Sync node container sizes with actual rendered content (before fitView)
    await this.syncAllNodeSizes();

    // Enable zoom, pan, fit view
    await finalizeSetup(this.area, this.editor, flowData.nodes?.length > 0);

    // Recalculate ALL socket positions now that DOM is fully laid out.
    // This fixes stale input socket positions that noderesized doesn't touch.
    await this.recalculateAllSockets();

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
      // biome-ignore lint/suspicious/noConsole: intentional warning for orphaned connection debugging
      console.warn(
        `Skipping connection ${connData.id}: source pin "${connData.source_pin}" not found on node ${connData.source_node_id}`,
      );
      return;
    }
    if (!targetNode.inputs[connData.target_pin]) {
      // biome-ignore lint/suspicious/noConsole: intentional warning for orphaned connection debugging
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

  /** Snapshots current positions for all editor nodes. */
  _snapshotPositions() {
    const positions = new Map();
    for (const node of this.editor.getNodes()) {
      const view = this.area.nodeViews.get(node.id);
      if (view) {
        positions.set(node.id, { x: view.position.x, y: view.position.y });
      }
    }
    return positions;
  },

  /** Persists a positions Map to the server via batch event. */
  _persistBatchPositions(positionsMap) {
    this.pushEvent("batch_update_positions", {
      positions: buildBatchPositions(positionsMap),
    });
  },

  async performAutoLayout() {
    if (this._autoLayoutInProgress) return;
    this._autoLayoutInProgress = true;

    try {
      const { ArrangeAppliers } = await import("rete-auto-arrange-plugin");
      const { AreaExtensions } = await import("rete-area-plugin");

      const prevPositions = this._snapshotPositions();

      // Compute and apply layout with animation
      const applier = new ArrangeAppliers.TransitionApplier({
        duration: 400,
        timingFunction: (t) => t * (2 - t),
      });

      this.enterLoadingFromServer();
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

      await AreaExtensions.zoomAt(this.area, this.editor.getNodes());

      const newPositions = this._snapshotPositions();
      this._persistBatchPositions(newPositions);

      // Record undo action
      if (this.history) {
        const { AutoLayoutAction } = await import("../flow_canvas/history_preset.js");
        this.history.add(new AutoLayoutAction(this, prevPositions, newPositions));
      }
    } catch (error) {
      // biome-ignore lint/suspicious/noConsole: error feedback for unlikely ELK layout failure
      console.error("Auto-layout failed:", error);
    } finally {
      this._autoLayoutInProgress = false;
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
    this.floatingToolbar?.hide();
    if (this.el.parentElement?.__floatingToolbar) {
      delete this.el.parentElement.__floatingToolbar;
    }
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
