/**
 * Event handler bindings for the flow canvas.
 *
 * Sets up Rete.js area pipes and LiveView handleEvent bindings.
 */

import { createFloatingPopover } from "../utils/floating_popover.js";

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
  if (el) el.editing = false;

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

  // Node position changes (drag) — skip during server-initiated loads
  hook.area.addPipe((context) => {
    if (context.type === "nodetranslated") {
      if (hook.isLoadingFromServer) return context;
      const node = hook.editor.getNode(context.data.id);
      if (node?.nodeId) {
        hook.editorHandlers.debounceNodeMoved(node.nodeId, context.data.position);
        // Hide toolbar during drag
        hook.floatingToolbar?.setDragging(true);
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
          const reteNode = hook.editor.getNode(context.data.id);
          if (reteNode?.nodeType === "dialogue") {
            enterInlineEdit(hook, context.data.id);
          } else {
            hook.pushEvent("node_double_clicked", { id: node.nodeId });
          }
        } else {
          hook.pushEvent("node_selected", { id: node.nodeId });
        }

        // Show floating toolbar
        hook.floatingToolbar?.show(node.nodeId);
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

    if (field === "text") {
      // Wrap plain text in <p> tags for rich text storage, preserving line breaks
      const escaped = value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      const content = escaped
        ? escaped
            .split("\n")
            .map((line) => `<p>${line || "<br>"}</p>`)
            .join("")
        : "";
      hook.pushEvent("update_node_text", { id: reteNode.nodeId, content });
    } else {
      hook.pushEvent("update_node_field", { field, value });
    }
  });

  // Speaker combobox — opens a searchable popover from the inline edit header
  hook._speakerPopover = null;
  hook.el.addEventListener("speaker-select-open", (e) => {
    const trigger = e.detail.trigger;
    if (!trigger || !hook._inlineEditingNodeId) return;

    // Close existing popover if open
    if (hook._speakerPopover?.isOpen) {
      hook._speakerPopover.destroy();
      hook._speakerPopover = null;
      return;
    }

    const reteNode = hook.editor.getNode(hook._inlineEditingNodeId);
    if (!reteNode) return;
    const currentSpeakerId = reteNode.nodeData?.speaker_sheet_id;

    // Build sorted sheet list
    const sheetsMap = hook.sheetsMap || {};
    const sheets = Object.values(sheetsMap).sort((a, b) =>
      (a.name || "").localeCompare(b.name || ""),
    );

    // Create popover anchored to the trigger button
    const fp = createFloatingPopover(trigger, {
      class: "bg-base-200 border border-base-300 rounded-lg shadow-lg",
      width: "14rem",
      placement: "bottom-start",
      offset: 4,
    });

    // Build content
    const wrap = document.createElement("div");
    wrap.style.cssText = "display:flex;flex-direction:column;max-height:240px;";

    const searchInput = document.createElement("input");
    searchInput.type = "text";
    searchInput.placeholder = "Search…";
    searchInput.style.cssText =
      "padding:6px 8px;border:none;border-bottom:1px solid oklch(0.35 0 0);background:transparent;color:inherit;outline:none;font-size:13px;";
    wrap.appendChild(searchInput);

    const list = document.createElement("div");
    list.style.cssText = "overflow-y:auto;flex:1;padding:4px 0;";

    // "No speaker" option
    const noSpeakerBtn = document.createElement("button");
    noSpeakerBtn.textContent = "Dialogue";
    noSpeakerBtn.dataset.searchText = "dialogue";
    noSpeakerBtn.dataset.value = "";
    noSpeakerBtn.style.cssText =
      "display:block;width:100%;text-align:left;padding:4px 8px;font-size:13px;border:none;background:transparent;color:inherit;cursor:pointer;opacity:0.6;font-style:italic;";
    if (!currentSpeakerId) noSpeakerBtn.style.opacity = "1";
    list.appendChild(noSpeakerBtn);

    for (const sheet of sheets) {
      const btn = document.createElement("button");
      btn.textContent = sheet.name;
      btn.dataset.searchText = (sheet.name || "").toLowerCase();
      btn.dataset.value = String(sheet.id);
      btn.style.cssText =
        "display:block;width:100%;text-align:left;padding:4px 8px;font-size:13px;border:none;background:transparent;color:inherit;cursor:pointer;";
      if (String(sheet.id) === String(currentSpeakerId)) {
        btn.style.fontWeight = "600";
      }
      list.appendChild(btn);
    }

    wrap.appendChild(list);
    fp.el.appendChild(wrap);

    // Filter
    searchInput.addEventListener("input", () => {
      const q = searchInput.value.toLowerCase().trim();
      for (const btn of list.children) {
        const text = btn.dataset.searchText || "";
        btn.style.display = !q || text.includes(q) ? "" : "none";
      }
    });

    // Hover highlight
    list.addEventListener("mouseover", (ev) => {
      const btn = ev.target.closest("button");
      if (btn) btn.style.background = "oklch(0.35 0 0)";
    });
    list.addEventListener("mouseout", (ev) => {
      const btn = ev.target.closest("button");
      if (btn) btn.style.background = "transparent";
    });

    // Selection
    list.addEventListener("click", (ev) => {
      const btn = ev.target.closest("button");
      if (!btn) return;
      const value = btn.dataset.value || null;
      hook.pushEvent("update_node_field", {
        field: "speaker_sheet_id",
        value: value || null,
      });
      fp.destroy();
      hook._speakerPopover = null;
    });

    fp.open();
    requestAnimationFrame(() => searchInput.focus());
    hook._speakerPopover = fp;
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

  // ===== Floating Toolbar — reposition on pan/zoom =====

  // Reposition toolbar on canvas pan (area translate)
  hook.area.addPipe((context) => {
    if (context.type === "translated") {
      hook.floatingToolbar?.reposition();
    }
    return context;
  });

  // Reposition toolbar on zoom
  hook.area.addPipe((context) => {
    if (context.type === "zoomed") {
      hook.floatingToolbar?.reposition();
    }
    return context;
  });

  // Click on empty canvas — deselect node + hide toolbar
  hook.el.addEventListener("pointerdown", (e) => {
    // Only primary button (left click)
    if (e.button !== 0) return;
    const storyarnEl = e.composedPath().find((el) => el.tagName === "STORYARN-NODE");
    if (!storyarnEl && hook.selectedNodeId) {
      exitInlineEdit(hook);
      hook.pushEvent("deselect_node", {});
      hook.selectedNodeId = null;
      hook.floatingToolbar?.hide();
    }
  });

  // Detect drag end — show toolbar again after node move
  hook.el.addEventListener("pointerup", () => {
    hook.floatingToolbar?.setDragging(false);
  });
}
