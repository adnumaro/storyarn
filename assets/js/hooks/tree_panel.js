/**
 * TreePanel hook — manages tree panel pin state via localStorage.
 *
 * Reads the pinned state from localStorage on mount and pushes it to the server.
 * Listens for pin/unpin events to persist the state.
 */

const STORAGE_KEY = "storyarn:tree_panel:pinned";

export const TreePanel = {
  mounted() {
    // Read persisted pin state (default: true for new users)
    const stored = localStorage.getItem(STORAGE_KEY);
    const pinned = stored === null ? true : stored === "true";

    // Push the initial state to the server so it can set assigns
    this.pushEvent("tree_panel_init", { pinned });
  },

  updated() {
    // Persist pin state whenever the element updates
    const pinned = this.el.dataset.pinned === "true";
    localStorage.setItem(STORAGE_KEY, String(pinned));
  },

  destroyed() {
    // Nothing to clean up
  },
};
