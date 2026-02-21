/**
 * Keyboard shortcuts handler for the flow canvas.
 */

/** Returns true if the element is an editable form field or contentEditable. */
function isEditable(el) {
  const tag = el.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
}

/**
 * Creates the keyboard handler with methods bound to the hook context.
 * @param {Object} hook - The FlowCanvas hook instance
 * @param {Object} lockHandler - The lock handler for checking node locks
 * @returns {Object} Handler methods
 */
export function createKeyboardHandler(hook, lockHandler) {
  return {
    /**
     * Initializes keyboard event listener.
     */
    init() {
      this._keydownListener = (e) => this.handleKeyboard(e);
      document.addEventListener("keydown", this._keydownListener);
    },

    /**
     * Handles keyboard events for shortcuts.
     * @param {KeyboardEvent} e - The keyboard event
     */
    handleKeyboard(e) {
      // Navigation history: Alt+Left / Alt+Right (works even in inputs)
      if (e.altKey && !e.ctrlKey && !e.metaKey && !e.shiftKey) {
        if (e.key === "ArrowLeft") {
          e.preventDefault();
          hook.pushEvent("nav_back", {});
          return;
        }
        if (e.key === "ArrowRight") {
          e.preventDefault();
          hook.pushEvent("nav_forward", {});
          return;
        }
      }

      // Debug shortcuts — work even when typing in inputs (except Ctrl+Shift+D toggle)
      const debugActive = !!hook.el
        .closest("[id]")
        ?.parentElement?.querySelector("[data-debug-active]");

      // Ctrl+Shift+D / Cmd+Shift+D — toggle debug mode (always available)
      if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === "D") {
        e.preventDefault();
        hook.pushEvent(debugActive ? "debug_stop" : "debug_start", {});
        return;
      }

      if (debugActive) {
        // F10 — step forward
        if (e.key === "F10") {
          e.preventDefault();
          hook.pushEvent("debug_step", {});
          return;
        }

        // F9 — step back
        if (e.key === "F9") {
          e.preventDefault();
          hook.pushEvent("debug_step_back", {});
          return;
        }

        // F5 — toggle play/pause
        if (e.key === "F5") {
          e.preventDefault();
          const autoPlaying = !!hook.el
            .closest("[id]")
            ?.parentElement?.querySelector("[data-debug-active] [phx-click='debug_pause']");
          hook.pushEvent(autoPlaying ? "debug_pause" : "debug_play", {});
          return;
        }

        // F6 — reset
        if (e.key === "F6") {
          e.preventDefault();
          hook.pushEvent("debug_reset", {});
          return;
        }
      }

      // Undo — Ctrl+Z / Cmd+Z
      if ((e.ctrlKey || e.metaKey) && e.key === "z" && !e.shiftKey) {
        if (isEditable(e.target)) return;
        e.preventDefault();
        hook.history?.undo();
        return;
      }

      // Redo — Ctrl+Y / Cmd+Y / Ctrl+Shift+Z / Cmd+Shift+Z
      if ((e.ctrlKey || e.metaKey) && (e.key === "y" || (e.key === "z" && e.shiftKey))) {
        if (isEditable(e.target)) return;
        e.preventDefault();
        hook.history?.redo();
        return;
      }

      // Ignore when typing in inputs for non-debug shortcuts
      if (isEditable(e.target)) return;

      // Delete/Backspace - delete selected node (not when builder panel is open)
      if ((e.key === "Delete" || e.key === "Backspace") && hook.selectedNodeId) {
        if (document.getElementById("builder-panel-content")) return;
        e.preventDefault();
        if (lockHandler.isNodeLocked(hook.selectedNodeId)) return;
        hook.pushEvent("delete_node", { id: hook.selectedNodeId });
        hook.selectedNodeId = null;
        hook.floatingToolbar?.hide();
        return;
      }

      // Ctrl+D / Cmd+D - duplicate selected node
      if ((e.ctrlKey || e.metaKey) && e.key === "d" && hook.selectedNodeId) {
        e.preventDefault();
        hook.pushEvent("duplicate_node", { id: hook.selectedNodeId });
        return;
      }

      // E — open editor/builder for selected node
      if (e.key === "e" && !e.ctrlKey && !e.metaKey && hook.selectedNodeId) {
        const reteNode = hook.nodeMap?.get(hook.selectedNodeId);
        if (!reteNode) return;
        const nodeType = reteNode.nodeType;

        if (nodeType === "dialogue") {
          e.preventDefault();
          hook.pushEvent("open_screenplay", {});
        } else if (nodeType === "condition" || nodeType === "instruction") {
          e.preventDefault();
          hook.pushEvent("open_builder", {});
        }
        return;
      }

      // Escape — priority chain: editor → builder → toolbar → deselect
      if (e.key === "Escape") {
        e.preventDefault();

        const editorOpen = !!document.getElementById("screenplay-editor-container");
        const builderOpen = !!document.getElementById("builder-panel-content");

        if (editorOpen) {
          hook.pushEvent("close_editor", {});
        } else if (builderOpen) {
          hook.pushEvent("close_builder", {});
        } else if (hook.selectedNodeId) {
          hook.pushEvent("deselect_node", {});
          hook.selectedNodeId = null;
          hook.floatingToolbar?.hide();
        }
        return;
      }
    },

    /**
     * Cleans up keyboard event listener.
     */
    destroy() {
      if (this._keydownListener) {
        document.removeEventListener("keydown", this._keydownListener);
      }
    },
  };
}
