/**
 * TreeToggle hook for expand/collapse functionality with localStorage persistence.
 *
 * Usage: Add phx-hook="TreeToggle" and data-node-id="unique-id" to the toggle button.
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
    this.el.addEventListener("click", (e) => {
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
    });
  },
};
