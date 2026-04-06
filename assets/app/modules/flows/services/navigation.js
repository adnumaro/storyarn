/**
 * Navigation handler for Hub ↔ Jump cross-referencing (V2 Vue-native).
 *
 * Provides animated highlight and auto-zoom between related nodes.
 * Replaces V1 navigation_handler.js (no Lit, no storyarn-node queries).
 */

import { AreaExtensions } from "rete-area-plugin";
import { NODE_CONFIGS } from "../lib/node-configs.js";

const HIGHLIGHT_DURATION = 2500;

function nodeColor(node) {
  return node.nodeData?.color_hex || NODE_CONFIGS[node.nodeType]?.color || "#6b7280";
}

function findHubByHubId(nodeMap, hubId) {
  for (const [dbId, node] of nodeMap) {
    if (node.nodeType === "hub" && node.nodeData?.hub_id === hubId) {
      return { dbId, reteNode: node };
    }
  }
  return null;
}

function findJumpsForHub(nodeMap, hubId) {
  const results = [];
  for (const [dbId, node] of nodeMap) {
    if (node.nodeType === "jump" && node.nodeData?.target_hub_id === hubId) {
      results.push({ dbId, reteNode: node });
    }
  }
  return results;
}

/**
 * Finds the [data-testid="node"] element for a Rete node ID.
 */
function findNodeElement(area, reteId) {
  const view = area.nodeViews.get(reteId);
  if (!view) {
    return null;
  }
  return view.element.querySelector("[data-testid='node']");
}

export function navigation(area, nodeMap, pushEvent) {
  let highlightedElements = [];
  let highlightTimer = null;

  function clearHighlights() {
    if (highlightTimer) {
      clearTimeout(highlightTimer);
      highlightTimer = null;
    }
    for (const el of highlightedElements) {
      el.classList.remove("nav-highlight");
      el.style.removeProperty("--highlight-color");
    }
    highlightedElements = [];
  }

  function highlightNodes(reteNodeIds, hexColor) {
    clearHighlights();

    for (const reteId of reteNodeIds) {
      const el = findNodeElement(area, reteId);
      if (!el) {
        continue;
      }

      el.style.setProperty("--highlight-color", hexColor);
      el.classList.add("nav-highlight");
      highlightedElements.push(el);
    }

    highlightTimer = setTimeout(clearHighlights, HIGHLIGHT_DURATION);
  }

  return {
    navigateToHub(jumpDbId) {
      const jumpNode = nodeMap.get(jumpDbId);
      if (!jumpNode) {
        return;
      }

      const targetHubId = jumpNode.nodeData?.target_hub_id;
      if (!targetHubId) {
        return;
      }

      const hub = findHubByHubId(nodeMap, targetHubId);
      if (!hub) {
        return;
      }

      AreaExtensions.zoomAt(area, [jumpNode, hub.reteNode]);
      highlightNodes([hub.reteNode.id], nodeColor(hub.reteNode));
      pushEvent("node_selected", { id: hub.dbId });
    },

    navigateToNode(nodeDbId) {
      const node = nodeMap.get(nodeDbId);
      if (!node) {
        return;
      }

      AreaExtensions.zoomAt(area, [node]);
      highlightNodes([node.id], nodeColor(node));
      pushEvent("node_selected", { id: nodeDbId });
    },

    navigateToJumps(hubDbId) {
      const hubNode = nodeMap.get(hubDbId);
      if (!hubNode) {
        return;
      }

      const hubId = hubNode.nodeData?.hub_id;
      if (!hubId) {
        return;
      }

      const jumps = findJumpsForHub(nodeMap, hubId);
      if (jumps.length === 0) {
        return;
      }

      const allNodes = [hubNode, ...jumps.map((j) => j.reteNode)];
      AreaExtensions.zoomAt(area, allNodes);

      const jumpReteIds = jumps.map((j) => j.reteNode.id);
      highlightNodes(jumpReteIds, nodeColor(hubNode));
    },

    clearHighlights,

    destroy() {
      clearHighlights();
    },
  };
}
