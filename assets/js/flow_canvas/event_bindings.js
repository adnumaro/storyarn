/**
 * Event handler bindings for the flow canvas.
 *
 * Sets up Rete.js area pipes and LiveView handleEvent bindings.
 */

import { AreaExtensions } from "rete-area-plugin";
import { openSearchableDropdown } from "../utils/searchable_dropdown.js";

/**
 * Enters inline edit mode for a dialogue node.
 * @param {Object} hook - The FlowCanvas hook instance
 * @param {string} reteNodeId - The Rete editor node ID
 */
export function enterInlineEdit(hook, reteNodeId) {
  // Exit any existing inline edit first
  exitInlineEdit(hook);

  const nodeView = hook.area.nodeViews.get(reteNodeId);
  const el = nodeView?.element?.querySelector("storyarn-node");
  if (!el) return;

  el.editing = true;
  hook._inlineEditingNodeId = reteNodeId;
}

/**
 * Exits inline edit mode if active.
 * @param {Object} hook - The FlowCanvas hook instance
 */
export function exitInlineEdit(hook) {
  if (!hook._inlineEditingNodeId) return;

  // Close speaker combobox if open
  hook._speakerPopover?.destroy();
  hook._speakerPopover = null;

  const nodeView = hook.area.nodeViews.get(hook._inlineEditingNodeId);
  const el = nodeView?.element?.querySelector("storyarn-node");
  if (el) {
    // Blur the active input/textarea inside shadow DOM so its @blur handler
    // fires and saves data BEFORE we remove the editing UI
    const focused = el.shadowRoot?.activeElement;
    if (focused && (focused.tagName === "TEXTAREA" || focused.tagName === "INPUT")) {
      focused.blur();
    }
    el.editing = false;
  }

  hook._inlineEditingNodeId = null;
}

/**
 * Sets up all event handlers for the flow canvas.
 * @param {Object} hook - The FlowCanvas hook instance
 */
export function setupEventHandlers(hook) {
  hook.selectedNodeId = null;
  hook.lastNodeClickTime = 0;
  hook.lastClickedNodeId = null;

  // Node position changes (drag) — throttle for real-time collab, skip server loads
  hook.area.addPipe((context) => {
    if (context.type === "nodetranslated") {
      if (hook.isLoadingFromServer) return context;
      const node = hook.editor.getNode(context.data.id);
      if (node?.nodeId) {
        hook.editorHandlers.throttleNodeMoved(node.nodeId, context.data.position);
        hook.floatingToolbar?.setDragging(true);
      }
    }
    if (context.type === "nodedragged") {
      const node = hook.editor.getNode(context.data.id);
      if (node?.nodeId) {
        hook.editorHandlers.flushNodeMoved(node.nodeId);
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

        const prevSelectedNodeId = hook.selectedNodeId;
        hook.lastNodeClickTime = now;
        hook.lastClickedNodeId = node.nodeId;
        hook.selectedNodeId = node.nodeId;

        if (isDoubleClick) {
          const reteNode = hook.editor.getNode(context.data.id);
          const type = reteNode?.nodeType;
          if (type === "dialogue" || type === "annotation") {
            enterInlineEdit(hook, context.data.id);
          } else {
            hook.pushEvent("node_double_clicked", { id: node.nodeId });
          }
        } else {
          hook.pushEvent("node_selected", { id: node.nodeId });
        }

        // If switching to a different node, hide toolbar immediately to avoid
        // showing stale content — revealIfPrepared() shows it after server patch.
        // If same node, just reposition (content unchanged).
        if (prevSelectedNodeId !== node.nodeId) {
          hook.floatingToolbar?.prepare(node.nodeId);
        } else {
          hook.floatingToolbar?.show(node.nodeId);
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
  // Serialize node_moved events to prevent race conditions when
  // multiple position updates arrive faster than area.translate() resolves
  hook._nodeMoveQueue = Promise.resolve();
  hook.handleEvent("node_moved", (data) => {
    hook._nodeMoveQueue = hook._nodeMoveQueue
      .then(() => hook.editorHandlers.handleNodeMoved(data))
      // biome-ignore lint/suspicious/noConsole: intentional error logging
      .catch((err) => console.error("node_moved handler error:", err));
  });
  hook.handleEvent("node_added", (data) => hook.editorHandlers.handleNodeAdded(data));
  hook.handleEvent("node_removed", (data) => hook.editorHandlers.handleNodeRemoved(data));
  hook.handleEvent("node_restored", (data) => hook.editorHandlers.handleNodeRestored(data));
  // Serialize node_updated events to prevent race conditions when
  // multiple response additions/deletions trigger concurrent rebuilds
  hook._nodeUpdateQueue = Promise.resolve();
  hook.handleEvent("node_updated", (data) => {
    hook._nodeUpdateQueue = hook._nodeUpdateQueue
      .then(() => hook.editorHandlers.handleNodeUpdated(data))
      // biome-ignore lint/suspicious/noConsole: intentional error logging
      .catch((err) => console.error("node_updated handler error:", err));
  });
  hook.handleEvent("node_data_changed", (data) => hook.editorHandlers.handleNodeDataChanged(data));
  hook.handleEvent("flow_meta_changed", (data) => hook.editorHandlers.handleFlowMetaChanged(data));
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

  // Subflow navigation (composed from storyarn-node Shadow DOM)
  hook.el.addEventListener("navigate-to-subflow", (e) => {
    hook.pushEvent("navigate_to_subflow", { "flow-id": String(e.detail.flowId) });
  });

  // Exit flow reference navigation (composed from storyarn-node Shadow DOM)
  hook.el.addEventListener("navigate-to-exit-flow", (e) => {
    hook.pushEvent("navigate_to_exit_flow", { "flow-id": String(e.detail.flowId) });
  });

  // Referencing flow navigation (entry node → subflows that reference this flow)
  hook.el.addEventListener("navigate-to-referencing-flow", (e) => {
    hook.pushEvent("navigate_to_referencing_flow", { "flow-id": String(e.detail.flowId) });
  });

  // Inline edit save (composed from storyarn-node Shadow DOM)
  hook.el.addEventListener("node-inline-edit", (e) => {
    const { field, value } = e.detail;
    const reteNode = hook._inlineEditingNodeId
      ? hook.editor.getNode(hook._inlineEditingNodeId)
      : null;
    if (!reteNode) return;

    if (field === "text" && reteNode.nodeType === "annotation") {
      // Annotations store plain text directly (no rich-text wrapping)
      reteNode.nodeData = { ...reteNode.nodeData, text: value };
      hook.pushEvent("update_node_field", { field: "text", value });
    } else if (field === "text") {
      // Dialogue: wrap plain text in <p> tags for rich text storage, preserving line breaks
      const escaped = value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      const content = escaped
        ? escaped
            .split("\n")
            .map((line) => `<p>${line || "<br>"}</p>`)
            .join("")
        : "";
      // Optimistically update local nodeData so view mode shows new text immediately
      reteNode.nodeData = { ...reteNode.nodeData, text: content };
      hook.pushEvent("update_node_text", { id: reteNode.nodeId, content });
    } else {
      // Optimistically update local nodeData for non-text fields
      reteNode.nodeData = { ...reteNode.nodeData, [field]: value };
      hook.pushEvent("update_node_field", { field, value });
    }
  });

  // Speaker combobox — opens a searchable popover from the inline edit header
  hook._speakerPopover = null;
  hook.el.addEventListener("speaker-select-open", (e) => {
    const trigger = e.detail.trigger;
    if (!trigger || !hook._inlineEditingNodeId) return;

    if (hook._speakerPopover?.isOpen) {
      hook._speakerPopover.destroy();
      hook._speakerPopover = null;
      return;
    }

    const reteNode = hook.editor.getNode(hook._inlineEditingNodeId);
    if (!reteNode) return;

    const sheetsMap = hook.sheetsMap || {};
    const noSpeakerLabel = hook.labels?.no_speaker || "Dialogue";
    const currentSpeakerId = String(reteNode.nodeData?.speaker_sheet_id || "");

    hook._speakerPopover = openSearchableDropdown(trigger, {
      options: [
        { value: "", label: noSpeakerLabel, italic: true },
        ...Object.values(sheetsMap).map((s) => ({ value: String(s.id), label: s.name })),
      ],
      currentValue: currentSpeakerId,
      placeholder: hook.labels?.search || "Search…",
      onSelect: (value) => {
        const newSpeakerId = value || null;
        // Optimistic update: apply immediately so the header reflects the new speaker
        // without waiting for the server round-trip.
        // (handleNodeUpdated skips re-render while in inline-edit mode to protect text input)
        reteNode.nodeData = { ...reteNode.nodeData, speaker_sheet_id: newSpeakerId };
        reteNode._updateTs = Date.now();
        hook.area.update("node", reteNode.id);
        hook.pushEvent("update_node_field", {
          field: "speaker_sheet_id",
          value: newSpeakerId,
        });
        hook._speakerPopover = null;
      },
    });
  });

  // Handle server events - Debug
  hook.handleEvent("debug_highlight_node", (data) => hook.debugHandler.handleHighlightNode(data));
  hook.handleEvent("debug_highlight_connections", (data) =>
    hook.debugHandler.handleHighlightConnections(data),
  );
  hook.handleEvent("debug_clear_highlights", () => hook.debugHandler.handleClearHighlights());
  hook.handleEvent("debug_update_breakpoints", (data) =>
    hook.debugHandler.handleUpdateBreakpoints(data),
  );

  // Handle server events - Collaboration
  hook.handleEvent("cursor_update", (data) => hook.cursorHandler.handleCursorUpdate(data));
  hook.handleEvent("cursor_leave", (data) => hook.cursorHandler.handleCursorLeave(data));
  hook.handleEvent("locks_updated", (data) => hook.lockHandler.handleLocksUpdated(data));

  // Center canvas on a node, accounting for sidebar on desktop
  hook.handleEvent("center_on_node", async (data) => {
    const node = hook.nodeMap.get(data.id);
    if (!node) return;

    const SIDEBAR_WIDTH = data.sidebar_width ?? 600;
    const isFullscreen = window.innerWidth < 1280;

    if (isFullscreen) {
      await AreaExtensions.zoomAt(hook.area, [node]);
      return;
    }

    // Desktop: replicate zoomAt logic but for the visible area (left of sidebar)
    const view = hook.area.nodeViews.get(node.id);
    if (!view) return;

    // Get actual rendered dimensions from DOM (accounts for images, shadow DOM, etc.)
    // getBoundingClientRect gives screen pixels; divide by current zoom to get editor space
    const currentZoom = hook.area.area.transform.k;
    const rect = view.element.getBoundingClientRect();
    const nodeW = rect.width / currentZoom;
    const nodeH = rect.height / currentZoom;

    const w = hook.area.container.clientWidth - SIDEBAR_WIDTH;
    const h = hook.area.container.clientHeight;

    // Scale to fit node in visible area (same formula as zoomAt, scale=0.9)
    const k = Math.min((h / nodeH) * 0.9, (w / nodeW) * 0.9, 1);

    // Center of node in editor space
    const cx = view.position.x + nodeW / 2;
    const cy = view.position.y + nodeH / 2;

    // Translate so node center maps to center of visible area
    const tx = w / 2 - cx * k;
    const ty = h / 2 - cy * k;

    // Animate the pan+zoom transition with ease-in-out cubic
    const DURATION = 350;
    const start = { ...hook.area.area.transform };
    const startTime = performance.now();

    function easeInOutCubic(t) {
      return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
    }

    await new Promise((resolve) => {
      function frame(now) {
        const elapsed = now - startTime;
        const t = Math.min(elapsed / DURATION, 1);
        const e = easeInOutCubic(t);

        // Directly update transform and repaint — bypasses pipe events for perf
        hook.area.area.transform.x = start.x + (tx - start.x) * e;
        hook.area.area.transform.y = start.y + (ty - start.y) * e;
        hook.area.area.transform.k = start.k + (k - start.k) * e;
        hook.area.area.update();

        if (t < 1) {
          requestAnimationFrame(frame);
        } else {
          resolve();
        }
      }
      requestAnimationFrame(frame);
    });

    // Sync final state through Rete pipe system (fires translated/zoomed events)
    await hook.area.area.zoom(k, 0, 0);
    await hook.area.area.translate(tx, ty);
  });

  // ===== Floating Toolbar — reposition on pan/zoom =====

  // Reposition toolbars on canvas pan (area translate)
  hook.area.addPipe((context) => {
    if (context.type === "translated") {
      hook.floatingToolbar?.reposition();
    }
    return context;
  });

  // Reposition toolbars on zoom
  hook.area.addPipe((context) => {
    if (context.type === "zoomed") {
      hook.floatingToolbar?.reposition();
    }
    return context;
  });

  // Click on empty canvas — deselect node + annotations + hide toolbar
  hook.el.addEventListener("pointerdown", (e) => {
    // Only primary button (left click)
    if (e.button !== 0) return;
    const storyarnEl = e.composedPath().find((el) => el.tagName === "STORYARN-NODE");

    if (!storyarnEl && hook.selectedNodeId) {
      exitInlineEdit(hook);

      // If a sidebar panel is open, animate it out first.
      // The screenplay editor hook pushes "deselect_node" after animation.
      // The builder sidebar hook pushes "close_builder" (back to toolbar, no deselect).
      const editorEl = document.getElementById("dialogue-screenplay-editor");
      const builderEl = document.getElementById("builder-sidebar");

      if (editorEl) {
        editorEl.dispatchEvent(new CustomEvent("panel:close-deselect"));
      } else if (builderEl) {
        // Builder: close sidebar but keep node selected (goes back to toolbar mode)
        builderEl.dispatchEvent(new CustomEvent("panel:close"));
      } else {
        hook.pushEvent("deselect_node", {});
      }

      hook.selectedNodeId = null;
      hook.floatingToolbar?.hide();
    }
  });

  // Detect drag end — show toolbar again after node move
  hook.el.addEventListener("pointerup", () => {
    hook.floatingToolbar?.setDragging(false);
  });
}
