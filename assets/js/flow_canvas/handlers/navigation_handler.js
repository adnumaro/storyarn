/**
 * Navigation handler for Hub ↔ Jump cross-referencing.
 *
 * Provides animated highlight and auto-zoom between related Hub and Jump nodes.
 */

import { AreaExtensions } from "rete-area-plugin";

const HIGHLIGHT_DURATION = 2500;

/**
 * Finds the hub node matching a given hub_id.
 * @param {Object} hook - The FlowCanvas hook instance
 * @param {string} hubId - The hub_id to search for
 * @returns {{ dbId: number, reteNode: Object, nodeData: Object } | null}
 */
function findHubNodeByHubId(hook, hubId) {
  for (const [dbId, node] of hook.nodeMap) {
    if (node.nodeType === "hub" && node.nodeData?.hub_id === hubId) {
      return { dbId, reteNode: node, nodeData: node.nodeData };
    }
  }
  return null;
}

/**
 * Finds all jump nodes targeting a given hub_id.
 * @param {Object} hook - The FlowCanvas hook instance
 * @param {string} hubId - The hub_id to match against target_hub_id
 * @returns {Array<{ dbId: number, reteNode: Object }>}
 */
function findJumpNodesForHub(hook, hubId) {
  const results = [];
  for (const [dbId, node] of hook.nodeMap) {
    if (node.nodeType === "jump" && node.nodeData?.target_hub_id === hubId) {
      results.push({ dbId, reteNode: node });
    }
  }
  return results;
}

/**
 * Finds the storyarn-node DOM element for a given Rete node ID.
 * Queries the area container since nodeViews API varies across Rete versions.
 * @param {HTMLElement} container - The flow canvas container element
 * @param {string} reteId - The Rete node ID (e.g. "node-5")
 * @returns {HTMLElement|null}
 */
function findStoryarnNodeElement(container, reteId) {
  for (const el of container.querySelectorAll("storyarn-node")) {
    if (el.data?.id === reteId) return el;
  }
  return null;
}

/**
 * Creates the navigation handler with methods bound to the hook context.
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {Object} Handler methods
 */
export function createNavigationHandler(hook) {
  let highlightedElements = [];
  let highlightTimer = null;

  return {
    /**
     * Navigates from a jump node to its target hub.
     * Zooms to fit both nodes, highlights the hub, and selects it.
     * @param {number} jumpDbId - Database ID of the jump node
     */
    navigateToHub(jumpDbId) {
      const jumpNode = hook.nodeMap.get(jumpDbId);
      if (!jumpNode) return;

      const targetHubId = jumpNode.nodeData?.target_hub_id;
      if (!targetHubId) return;

      const hub = findHubNodeByHubId(hook, targetHubId);
      if (!hub) return;

      const hubColor = hub.nodeData.color_hex || "#8b5cf6";

      // Zoom to fit both nodes
      AreaExtensions.zoomAt(hook.area, [jumpNode, hub.reteNode]);

      // Highlight the hub
      this.highlightNodes([hub.reteNode.id], hubColor);

      // Select the hub (overrides Rete's selection of the jump)
      hook.pushEvent("node_selected", { id: hub.dbId });
    },

    /**
     * Navigates to a specific node by its database ID.
     * Zooms to the node, highlights it, and selects it.
     * @param {number} nodeDbId - Database ID of the target node
     */
    navigateToNode(nodeDbId) {
      const node = hook.nodeMap.get(nodeDbId);
      if (!node) return;

      const color = node.nodeData?.color_hex || "#8b5cf6";

      AreaExtensions.zoomAt(hook.area, [node]);
      this.highlightNodes([node.id], color);
      hook.pushEvent("node_selected", { id: nodeDbId });
    },

    /**
     * Navigates from a hub node to all jump nodes targeting it.
     * Zooms to fit all related nodes and highlights the jumps.
     * @param {number} hubDbId - Database ID of the hub node
     */
    navigateToJumps(hubDbId) {
      const hubNode = hook.nodeMap.get(hubDbId);
      if (!hubNode) return;

      const hubId = hubNode.nodeData?.hub_id;
      if (!hubId) return;

      const jumps = findJumpNodesForHub(hook, hubId);
      if (jumps.length === 0) return;

      const hubColor = hubNode.nodeData.color_hex || "#8b5cf6";

      // Zoom to fit hub + all jumps
      const allNodes = [hubNode, ...jumps.map((j) => j.reteNode)];
      AreaExtensions.zoomAt(hook.area, allNodes);

      // Highlight the jump nodes
      const jumpReteIds = jumps.map((j) => j.reteNode.id);
      this.highlightNodes(jumpReteIds, hubColor);
    },

    /**
     * Applies a pulsing highlight animation to the given nodes.
     * Uses DOM queries to find storyarn-node elements reliably.
     * @param {string[]} reteNodeIds - Rete node IDs to highlight
     * @param {string} hexColor - CSS color for the highlight
     */
    highlightNodes(reteNodeIds, hexColor) {
      this.clearHighlights();

      for (const reteId of reteNodeIds) {
        const el = findStoryarnNodeElement(hook.el, reteId);
        if (!el) continue;

        el.style.setProperty("--highlight-color", hexColor);
        el.classList.add("nav-highlight");
        highlightedElements.push(el);
      }

      highlightTimer = setTimeout(() => {
        this.clearHighlights();
      }, HIGHLIGHT_DURATION);
    },

    /**
     * Removes all active highlight animations.
     */
    clearHighlights() {
      if (highlightTimer) {
        clearTimeout(highlightTimer);
        highlightTimer = null;
      }
      for (const el of highlightedElements) {
        el.classList.remove("nav-highlight");
        el.style.removeProperty("--highlight-color");
      }
      highlightedElements = [];
    },

    /**
     * Cleans up all timers.
     */
    destroy() {
      this.clearHighlights();
    },
  };
}
