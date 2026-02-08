/**
 * Debug handler for the flow debugger visual feedback.
 *
 * Manages CSS classes on storyarn-node elements to show debug state:
 * - `.debug-current`  — pulsing highlight on the node being evaluated
 * - `.debug-visited`  — subtle border on already-visited nodes
 * - `.debug-waiting`  — amber pulse when waiting for user input
 * - `.debug-error`    — red indicator when node caused an error
 *
 * Also handles auto-scrolling to the current node on each step.
 */

import { AreaExtensions } from "rete-area-plugin";

/**
 * Finds the storyarn-node DOM element for a given Rete node ID.
 * @param {HTMLElement} container - The flow canvas container element
 * @param {string} reteId - The Rete node ID (e.g. "node-5")
 * @returns {HTMLElement|null}
 */
function findNodeElement(container, reteId) {
  for (const el of container.querySelectorAll("storyarn-node")) {
    if (el.data?.id === reteId) return el;
  }
  return null;
}

/**
 * Creates the debug handler with methods bound to the hook context.
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {Object} Handler methods
 */
export function createDebugHandler(hook) {
  let currentEl = null;
  let visitedEls = new Set();

  return {
    /**
     * Handles the debug_highlight_node push event from LiveView.
     * Marks the current node, all visited nodes, and scrolls to current.
     *
     * @param {{ node_id: number, status: string, execution_path: number[] }} data
     */
    handleHighlightNode(data) {
      const { node_id, status, execution_path } = data;

      // 1. Remove previous "current" highlight
      if (currentEl) {
        currentEl.classList.remove("debug-current", "debug-waiting");
        // Keep debug-visited on it since it was visited
        currentEl.classList.add("debug-visited");
      }

      // 2. Mark all nodes in execution path as visited
      for (const dbId of execution_path || []) {
        const reteNode = hook.nodeMap.get(dbId);
        if (!reteNode) continue;

        const el = findNodeElement(hook.el, reteNode.id);
        if (!el || visitedEls.has(el)) continue;

        el.classList.add("debug-visited");
        visitedEls.add(el);
      }

      // 3. Highlight current node
      const currentNode = hook.nodeMap.get(node_id);
      if (!currentNode) return;

      const el = findNodeElement(hook.el, currentNode.id);
      if (!el) return;

      // Remove visited style on current (current takes precedence)
      el.classList.remove("debug-visited");

      if (status === "waiting_input") {
        el.classList.add("debug-waiting");
      } else if (status === "finished") {
        el.classList.add("debug-current");
        // No pulsing for finished — just a static highlight
      } else {
        el.classList.add("debug-current");
      }

      currentEl = el;
      visitedEls.add(el);

      // 4. Scroll canvas to center on current node
      AreaExtensions.zoomAt(hook.area, [currentNode], { scale: undefined });
    },

    /**
     * Removes all debug visual overlays from the canvas.
     */
    handleClearHighlights() {
      // Clear current
      if (currentEl) {
        currentEl.classList.remove("debug-current", "debug-waiting");
        currentEl = null;
      }

      // Clear all visited
      for (const el of visitedEls) {
        el.classList.remove("debug-visited", "debug-current", "debug-waiting", "debug-error");
      }
      visitedEls = new Set();
    },

    /**
     * Cleans up all debug state.
     */
    destroy() {
      this.handleClearHighlights();
    },
  };
}
