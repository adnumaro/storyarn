/**
 * TreeToggle hook for expand/collapse functionality with localStorage persistence.
 *
 * Usage: Add phx-hook="TreeToggle" and data-node-id="unique-id" to the toggle button.
 */
export const TreeToggle = {
  mounted() {
    const nodeId = this.el.dataset.nodeId;
    const content = document.getElementById(`tree-content-${nodeId}`);
    const chevron = this.el.querySelector("[data-chevron]");

    // Restore state from localStorage
    const savedState = localStorage.getItem(`tree-${nodeId}`);
    if (savedState !== null) {
      const expanded = savedState === "true";
      if (content) {
        content.classList.toggle("hidden", !expanded);
      }
      if (chevron) {
        chevron.classList.toggle("rotate-90", expanded);
      }
    }

    // Handle click events
    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();

      if (content) {
        content.classList.toggle("hidden");
        const expanded = !content.classList.contains("hidden");

        if (chevron) {
          chevron.classList.toggle("rotate-90", expanded);
        }

        // Save state to localStorage
        localStorage.setItem(`tree-${nodeId}`, expanded);
      }
    });
  },
};
