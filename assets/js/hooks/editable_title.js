/**
 * EditableTitle hook for inline page title editing.
 * Works like Notion - transparent editing with auto-save.
 */
export const EditableTitle = {
  mounted() {
    this.originalName = this.el.dataset.name;
    this.debounceTimer = null;

    // Listen for restore events from server
    this.handleEvent("restore_page_content", ({ name }) => {
      this.el.textContent = name;
      this.originalName = name;
      this.el.dataset.name = name;
    });

    // Save on input with debounce
    this.el.addEventListener("input", () => {
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
        this.el.textContent = this.originalName;
        this.el.blur();
      }
    });

    // Save on blur (if changed)
    this.el.addEventListener("blur", () => {
      this.saveNow();
    });

    // Prevent line breaks
    this.el.addEventListener("paste", (e) => {
      e.preventDefault();
      const text = e.clipboardData.getData("text/plain").replace(/\n/g, " ");
      document.execCommand("insertText", false, text);
    });
  },

  debounceSave() {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.saveNow();
    }, 500);
  },

  saveNow() {
    clearTimeout(this.debounceTimer);
    const name = this.el.textContent.trim();

    // Only save if changed and not empty
    if (name && name !== this.originalName) {
      this.originalName = name;
      const target = this.el.dataset.target;
      const payload = { name: name };

      if (target) {
        this.pushEventTo(target, "save_name", payload);
      } else {
        this.pushEvent("save_name", payload);
      }
    } else if (!name) {
      // Revert to original if empty
      this.el.textContent = this.originalName;
    }
  },

  destroyed() {
    clearTimeout(this.debounceTimer);
  },
};
