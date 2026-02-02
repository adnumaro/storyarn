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
      hook.keyboardHandler = (e) => this.handleKeyboard(e);
      document.addEventListener("keydown", hook.keyboardHandler);
    },

    /**
     * Handles keyboard events for shortcuts.
     * @param {KeyboardEvent} e - The keyboard event
     */
    handleKeyboard(e) {
      // Ignore when typing in inputs
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
      if (hook.keyboardHandler) {
        document.removeEventListener("keydown", hook.keyboardHandler);
      }
    },
  };
}
