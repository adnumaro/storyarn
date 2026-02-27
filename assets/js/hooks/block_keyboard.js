/**
 * BlockKeyboard Hook
 *
 * Attached to the blocks container. Listens for keyboard shortcuts
 * when a block is selected (selected_block_id is set).
 *
 * Shortcuts:
 * - Delete/Backspace → delete_block
 * - Cmd+D / Ctrl+D   → duplicate_block
 * - Shift+ArrowUp    → move_block_up
 * - Shift+ArrowDown  → move_block_down
 * - Escape           → deselect_block
 */
export const BlockKeyboard = {
  mounted() {
    this._handleKeydown = (e) => {
      // Ignore when focus is inside an input, select, textarea, or contenteditable
      const tag = e.target.tagName;
      if (tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA" || e.target.isContentEditable) {
        return;
      }

      // Only act when a block is selected
      const selectedId = this.el.dataset.selectedBlockId;
      if (!selectedId) return;

      const isMod = e.metaKey || e.ctrlKey;

      if (e.key === "Delete" || e.key === "Backspace") {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "delete_block", {
          id: selectedId,
        });
      } else if (e.key === "d" && isMod) {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "duplicate_block", {
          id: selectedId,
        });
      } else if (e.key === "ArrowUp" && e.shiftKey) {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "move_block_up", {
          id: selectedId,
        });
      } else if (e.key === "ArrowDown" && e.shiftKey) {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "move_block_down", {
          id: selectedId,
        });
      } else if (e.key === "Escape") {
        e.preventDefault();
        this.pushEventTo(this.el.dataset.phxTarget, "deselect_block", {});
      }
    };

    document.addEventListener("keydown", this._handleKeydown);
  },

  destroyed() {
    document.removeEventListener("keydown", this._handleKeydown);
  },
};
