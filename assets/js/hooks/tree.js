/**
 * TreeToggle hook for expand/collapse functionality with localStorage persistence.
 *
 * Usage: Add phx-hook="TreeToggle", data-node-id="unique-id", and
 * data-expanded="true/false" (server-computed: true when selected item is a
 * descendant) to the toggle button.
 *
 * data-expanded triggers updated() whenever the server's expansion state
 * changes (e.g. the selected sheet moves in/out of this subtree), which
 * lets restoreState() re-apply the correct visibility even though the
 * tree-content div is a *sibling* of the hook element.
 */
export const TreeToggle = {
  mounted() {
    this.nodeId = this.el.dataset.nodeId;
    this.restoreState();
    this.setupClickHandler();
  },

  updated() {
    // Restore state after LiveView updates the DOM
    this.restoreState();
  },

  restoreState() {
    const content = document.getElementById(`tree-content-${this.nodeId}`);
    const chevron = this.el.querySelector("[data-chevron]");

    // Server says this folder contains the selected item → always keep it open.
    // This handles navigating *into* a subtree (auto-expand) and takes priority
    // over any previously-saved collapsed state.
    if (this.el.dataset.expanded === "true") {
      if (content) content.classList.remove("hidden");
      if (chevron) chevron.classList.add("rotate-90");
      return;
    }

    // Otherwise restore user's manual expand/collapse from localStorage.
    const savedState = localStorage.getItem(`tree-${this.nodeId}`);
    if (savedState !== null) {
      const expanded = savedState === "true";
      if (content) {
        content.classList.toggle("hidden", !expanded);
      }
      if (chevron) {
        chevron.classList.toggle("rotate-90", expanded);
      }
    }
  },

  setupClickHandler() {
    this._clickHandler = (e) => {
      e.preventDefault();
      e.stopPropagation();

      const content = document.getElementById(`tree-content-${this.nodeId}`);
      const chevron = this.el.querySelector("[data-chevron]");

      if (content) {
        content.classList.toggle("hidden");
        const expanded = !content.classList.contains("hidden");

        if (chevron) {
          chevron.classList.toggle("rotate-90", expanded);
        }

        // Save state to localStorage
        localStorage.setItem(`tree-${this.nodeId}`, expanded);
      }
    };
    this.el.addEventListener("click", this._clickHandler);
  },

  destroyed() {
    this.el.removeEventListener("click", this._clickHandler);
  },
};
