import { pushWithTarget } from "../utils/event_dispatcher";

/**
 * EditableShortcut hook for inline sheet/flow shortcut editing.
 * Similar to EditableTitle but with format validation.
 */
export const EditableShortcut = {
  mounted() {
    this.originalShortcut = this.el.dataset.shortcut || "";
    this.debounceTimer = null;

    // Listen for restore events from server
    this.handleEvent("restore_page_content", ({ shortcut }) => {
      if (shortcut === undefined) return;
      this.el.textContent = shortcut || "";
      this.originalShortcut = shortcut || "";
      this.el.dataset.shortcut = shortcut || "";
    });

    // Save on input with debounce
    this.el.addEventListener("input", () => {
      // Sanitize input: lowercase, remove invalid chars
      const sanitized = this.sanitize(this.el.textContent);
      if (sanitized !== this.el.textContent) {
        // Update content if sanitized is different
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        const offset = range.startOffset;

        this.el.textContent = sanitized;

        // Restore cursor position
        if (sanitized.length > 0) {
          const newRange = document.createRange();
          const textNode = this.el.firstChild;
          if (textNode) {
            newRange.setStart(textNode, Math.min(offset, sanitized.length));
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
          }
        }
      }
      this.debounceSave();
    });

    // Handle special keys
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        this.el.blur();
        this.saveNow();
      } else if (e.key === "Escape") {
        e.preventDefault();
        this.el.textContent = this.originalShortcut;
        this.el.blur();
      } else if (e.key === " ") {
        // No spaces allowed
        e.preventDefault();
      }
    });

    // Save on blur
    this.el.addEventListener("blur", () => {
      this.saveNow();
    });

    // Prevent paste with invalid characters
    this.el.addEventListener("paste", (e) => {
      e.preventDefault();
      const text = e.clipboardData.getData("text/plain");
      const sanitized = this.sanitize(text);
      document.execCommand("insertText", false, sanitized);
    });
  },

  sanitize(text) {
    // Lowercase, convert spaces/underscores to hyphens, only alphanumeric, dots, and hyphens
    return text
      .toLowerCase()
      .replace(/[\s_]+/g, "-") // Convert spaces/underscores to hyphens
      .replace(/[^a-z0-9.-]/g, "") // Remove invalid characters
      .replace(/-+/g, "-") // Collapse multiple hyphens
      .replace(/^[.-]+/, "") // Remove leading dots/hyphens
      .replace(/[.-]+$/, ""); // Remove trailing dots/hyphens
  },

  debounceSave() {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.saveNow();
    }, 500);
  },

  saveNow() {
    clearTimeout(this.debounceTimer);
    const shortcut = this.el.textContent.trim();

    // Only save if changed
    if (shortcut !== this.originalShortcut) {
      this.originalShortcut = shortcut;
      pushWithTarget(this, "save_shortcut", { shortcut: shortcut || null });
    }
  },

  destroyed() {
    clearTimeout(this.debounceTimer);
  },
};
