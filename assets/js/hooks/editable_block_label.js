import { pushWithTarget } from "../utils/event_dispatcher";

/**
 * EditableBlockLabel hook for inline block label editing.
 * Double-click to edit, blur/Enter to save, Escape to revert.
 */
export const EditableBlockLabel = {
  mounted() {
    this.originalLabel = this.el.dataset.label;
    this.blockId = this.el.dataset.blockId;

    this.el.addEventListener("dblclick", (e) => {
      e.stopPropagation();
      this.el.contentEditable = "true";
      this.el.focus();
      // Select all text
      const range = document.createRange();
      range.selectNodeContents(this.el);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    });

    // While editing, stop clicks from reaching parent (e.g. collapse toggle button)
    this.el.addEventListener("click", (e) => {
      if (this.el.contentEditable === "true") {
        e.stopPropagation();
      }
    });

    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        this.el.blur();
      } else if (e.key === "Escape") {
        e.preventDefault();
        this.el.textContent = this.originalLabel;
        this.el.contentEditable = "false";
      }
    });

    this.el.addEventListener("blur", () => {
      this.el.contentEditable = "false";
      const newLabel = this.el.textContent.trim();

      if (newLabel && newLabel !== this.originalLabel) {
        this.originalLabel = newLabel;
        pushWithTarget(this, "update_block_label", {
          id: this.blockId,
          label: newLabel,
        });
      } else if (!newLabel) {
        // Revert if empty
        this.el.textContent = this.originalLabel;
      }
    });

    // Prevent line breaks on paste
    this.el.addEventListener("paste", (e) => {
      e.preventDefault();
      const text = e.clipboardData.getData("text/plain").replace(/\n/g, " ");
      document.execCommand("insertText", false, text);
    });
  },
};
