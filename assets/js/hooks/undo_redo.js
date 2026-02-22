/**
 * Generic undo/redo keyboard shortcut hook.
 * Attach to any container element to enable Cmd+Z / Cmd+Shift+Z / Cmd+Y.
 * Skips when focus is in editable fields (inputs, textareas, contenteditable).
 */
export const UndoRedo = {
  mounted() {
    this.handleKeydown = (e) => {
      const mod = e.metaKey || e.ctrlKey;
      if (!mod) return;

      // Skip when editing in form fields
      const tag = e.target.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      if (e.target.isContentEditable) return;

      if (e.key === "z" && !e.shiftKey) {
        e.preventDefault();
        this.pushEvent("undo", {});
      } else if (e.key === "z" && e.shiftKey) {
        e.preventDefault();
        this.pushEvent("redo", {});
      } else if (e.key === "y") {
        e.preventDefault();
        this.pushEvent("redo", {});
      }
    };

    document.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown);
  },
};
