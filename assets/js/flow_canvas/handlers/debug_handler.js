/**
 * Debug handler for the flow debugger visual feedback.
 *
 * Manages CSS classes on storyarn-node elements to show debug state:
 * - `.debug-current`  — pulsing highlight on the node being evaluated
 * - `.debug-visited`  — subtle border on already-visited nodes
 * - `.debug-waiting`  — amber pulse when waiting for user input
 * - `.debug-error`    — red indicator when node caused an error
 *
 * Connection highlighting uses CSS custom properties on the connection
 * view wrapper div. These properties inherit through Shadow DOM boundaries
 * into <storyarn-connection>'s static styles.
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
  let activeConnView = null;
  let visitedConnViews = new Set();

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
     * Handles the debug_highlight_connections push event from LiveView.
     * Sets CSS custom properties on connection view wrapper divs.
     * These properties inherit through Shadow DOM into storyarn-connection styles.
     *
     * @param {{ active_connection: {source_node_id: number, target_node_id: number, source_pin: string}|null, execution_path: number[] }} data
     */
    handleHighlightConnections(data) {
      const { active_connection, execution_path } = data;

      // 1. Demote previous active connection to visited
      if (activeConnView) {
        clearConnDebugProps(activeConnView);
        setConnVisitedProps(activeConnView);
        visitedConnViews.add(activeConnView);
        activeConnView = null;
      }

      // 2. Mark all path connections as visited
      if (execution_path && execution_path.length >= 2) {
        for (let i = 0; i < execution_path.length - 1; i++) {
          const viewEl = findConnectionViewElement(hook, execution_path[i], execution_path[i + 1]);
          if (viewEl && !visitedConnViews.has(viewEl)) {
            setConnVisitedProps(viewEl);
            visitedConnViews.add(viewEl);
          }
        }
      }

      // 3. Highlight current active connection
      if (active_connection) {
        const viewEl = findConnectionViewElement(
          hook,
          active_connection.source_node_id,
          active_connection.target_node_id,
        );
        if (viewEl) {
          clearConnDebugProps(viewEl);
          setConnActiveProps(viewEl);
          activeConnView = viewEl;
        }
      }
    },

    /**
     * Removes all debug visual overlays from the canvas.
     */
    handleClearHighlights() {
      // Clear current node
      if (currentEl) {
        currentEl.classList.remove("debug-current", "debug-waiting");
        currentEl = null;
      }

      // Clear all visited nodes
      for (const el of visitedEls) {
        el.classList.remove("debug-visited", "debug-current", "debug-waiting", "debug-error");
      }
      visitedEls = new Set();

      // Clear active connection
      if (activeConnView) {
        clearConnDebugProps(activeConnView);
        activeConnView = null;
      }

      // Clear all visited connections
      for (const el of visitedConnViews) {
        clearConnDebugProps(el);
      }
      visitedConnViews = new Set();
    },

    /**
     * Cleans up all debug state.
     */
    destroy() {
      this.handleClearHighlights();
    },
  };
}

/**
 * Finds the connection view wrapper element for a connection between two DB node IDs.
 * Returns view.element (the outer div) where CSS custom properties can be set
 * to inherit through Shadow DOM into <storyarn-connection>.
 *
 * @param {Object} hook - The FlowCanvas hook instance
 * @param {number} sourceDbId - Source node DB ID
 * @param {number} targetDbId - Target node DB ID
 * @returns {HTMLElement|null} The view wrapper element, or null
 */
function findConnectionViewElement(hook, sourceDbId, targetDbId) {
  for (const conn of hook.editor.getConnections()) {
    const srcNode = hook.editor.getNode(conn.source);
    const tgtNode = hook.editor.getNode(conn.target);

    if (srcNode?.nodeId === sourceDbId && tgtNode?.nodeId === targetDbId) {
      const view = hook.area.connectionViews.get(conn.id);
      if (view) return view.element;
    }
  }
  return null;
}

/**
 * Sets CSS custom properties for the "active" debug state on a connection view element.
 * @param {HTMLElement} viewEl - The connection view wrapper div
 */
function setConnActiveProps(viewEl) {
  viewEl.style.setProperty("--conn-stroke", "oklch(var(--p, 0.6 0.2 250))");
  viewEl.style.setProperty("--conn-stroke-width", "3px");
  viewEl.style.setProperty("--conn-dash", "8 4");
  viewEl.style.setProperty("--conn-animation", "debug-flow 0.6s linear infinite");
}

/**
 * Sets CSS custom properties for the "visited" debug state on a connection view element.
 * @param {HTMLElement} viewEl - The connection view wrapper div
 */
function setConnVisitedProps(viewEl) {
  viewEl.style.setProperty("--conn-stroke", "oklch(var(--p, 0.6 0.2 250) / 0.3)");
  viewEl.style.setProperty("--conn-stroke-width", "2px");
  viewEl.style.removeProperty("--conn-dash");
  viewEl.style.removeProperty("--conn-animation");
}

/**
 * Removes all debug CSS custom properties from a connection view element.
 * @param {HTMLElement} viewEl - The connection view wrapper div
 */
function clearConnDebugProps(viewEl) {
  viewEl.style.removeProperty("--conn-stroke");
  viewEl.style.removeProperty("--conn-stroke-width");
  viewEl.style.removeProperty("--conn-dash");
  viewEl.style.removeProperty("--conn-animation");
}
