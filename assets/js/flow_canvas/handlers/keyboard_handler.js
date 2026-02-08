/**
 * Keyboard shortcuts handler for the flow canvas.
 */

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

      // Ignore when typing in inputs for non-debug shortcuts
      if (
        e.target.tagName === "INPUT" ||
        e.target.tagName === "TEXTAREA" ||
        e.target.isContentEditable
      ) {
        return;
      }

      // Delete/Backspace - delete selected node
      if ((e.key === "Delete" || e.key === "Backspace") && hook.selectedNodeId) {
        e.preventDefault();
        if (lockHandler.isNodeLocked(hook.selectedNodeId)) return;
        hook.pushEvent("delete_node", { id: hook.selectedNodeId });
        hook.selectedNodeId = null;
        return;
      }

      // Ctrl+D / Cmd+D - duplicate selected node
      if ((e.ctrlKey || e.metaKey) && e.key === "d" && hook.selectedNodeId) {
        e.preventDefault();
        hook.pushEvent("duplicate_node", { id: hook.selectedNodeId });
        return;
      }

      // Escape - deselect node
      if (e.key === "Escape" && hook.selectedNodeId) {
        e.preventDefault();
        hook.pushEvent("deselect_node", {});
        hook.selectedNodeId = null;
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
