/**
 * Navigation handler for Hub <-> Jump cross-referencing (V2 Vue-native).
 *
 * Provides animated highlight and auto-zoom between related nodes.
 * Replaces V1 navigation_handler.js (no Lit, no storyarn-node queries).
 */

import { AreaExtensions, type AreaPlugin } from "rete-area-plugin";
import type { NodeEditor } from "rete";
import type { FlowNode } from "../lib/flow-node";
import { createFlowGraphQueries } from "../lib/flowGraphQueries";
import { NODE_CONFIGS } from "../lib/node-configs";
import type { FlowSchemes, FlowAreaExtra } from "../lib/rete-schemes";

const HIGHLIGHT_DURATION = 2500;

export interface ConnectionRef {
  sourceDbId: number;
  sourcePin: string | null;
  targetDbId: number;
  targetPin: string | null;
}

export interface NavigationHandler {
  navigateToHub(jumpDbId: number): void;
  navigateToNode(nodeDbId: number): void;
  navigateToJumps(hubDbId: number): void;
  navigateToConnection(ref: ConnectionRef): void;
  clearHighlights(): void;
  destroy(): void;
}

function nodeColor(node: FlowNode): string {
  return (
    (node.nodeData?.color_hex as string) ||
    NODE_CONFIGS[node.nodeType as keyof typeof NODE_CONFIGS]?.color ||
    "#6b7280"
  );
}

function findHubByHubId(
  nodeMap: Map<string | number, FlowNode>,
  hubId: string | number,
): { dbId: string | number; reteNode: FlowNode } | null {
  for (const [dbId, node] of nodeMap) {
    if (node.nodeType === "hub" && node.nodeData?.hub_id === hubId) {
      return { dbId, reteNode: node };
    }
  }
  return null;
}

function findJumpsForHub(
  nodeMap: Map<string | number, FlowNode>,
  hubId: string | number,
): { dbId: string | number; reteNode: FlowNode }[] {
  const results: { dbId: string | number; reteNode: FlowNode }[] = [];
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
function findNodeElement(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  reteId: string,
): HTMLElement | null {
  const view = area.nodeViews.get(reteId);
  if (!view) {
    return null;
  }
  return view.element.querySelector("[data-testid='node']") as HTMLElement | null;
}

export function navigation(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  nodeMap: Map<string | number, FlowNode>,
  pushEvent: (event: string, payload: Record<string, unknown>) => void,
  editor?: NodeEditor<FlowSchemes>,
): NavigationHandler {
  let highlightedElements: HTMLElement[] = [];
  let highlightedConnectionEl: HTMLElement | null = null;
  let highlightTimer: ReturnType<typeof setTimeout> | null = null;

  function clearHighlights(): void {
    if (highlightTimer) {
      clearTimeout(highlightTimer);
      highlightTimer = null;
    }
    for (const el of highlightedElements) {
      el.classList.remove("nav-highlight");
      el.style.removeProperty("--highlight-color");
    }
    highlightedElements = [];

    if (highlightedConnectionEl) {
      highlightedConnectionEl.style.removeProperty("--conn-stroke");
      highlightedConnectionEl.style.removeProperty("--conn-stroke-width");
      highlightedConnectionEl.style.removeProperty("--conn-dash");
      highlightedConnectionEl.style.removeProperty("--conn-animation");
      highlightedConnectionEl = null;
    }
  }

  // Same CSS-variable mechanism the debug panel uses on FlowConnection.vue,
  // scoped to a single finding-evidence highlight with auto-clear.
  function highlightConnectionEl(viewEl: HTMLElement): void {
    clearHighlights();
    viewEl.style.setProperty("--conn-stroke", "var(--color-primary, #7c3aed)");
    viewEl.style.setProperty("--conn-stroke-width", "3px");
    viewEl.style.setProperty("--conn-dash", "8 4");
    viewEl.style.setProperty("--conn-animation", "debug-flow 0.6s linear infinite");
    highlightedConnectionEl = viewEl;
    highlightTimer = setTimeout(clearHighlights, HIGHLIGHT_DURATION);
  }

  function highlightNodes(reteNodeIds: string[], hexColor: string): void {
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
    navigateToHub(jumpDbId: number): void {
      const jumpNode = nodeMap.get(jumpDbId);
      if (!jumpNode) {
        return;
      }

      const targetHubId = jumpNode.nodeData?.target_hub_id;
      if (!targetHubId) {
        return;
      }

      const hub = findHubByHubId(nodeMap, targetHubId as string | number);
      if (!hub) {
        return;
      }

      AreaExtensions.zoomAt(area, [jumpNode, hub.reteNode]);
      highlightNodes([hub.reteNode.id], nodeColor(hub.reteNode));
      pushEvent("node_selected", { id: hub.dbId });
    },

    navigateToNode(nodeDbId: number): void {
      const node = nodeMap.get(nodeDbId);
      if (!node) {
        return;
      }

      AreaExtensions.zoomAt(area, [node]);
      highlightNodes([node.id], nodeColor(node));
      pushEvent("node_selected", { id: nodeDbId });
    },

    navigateToConnection(ref: ConnectionRef): void {
      const sourceNode = nodeMap.get(ref.sourceDbId);
      const targetNode = nodeMap.get(ref.targetDbId);
      if (!sourceNode || !targetNode || !editor) {
        return;
      }

      AreaExtensions.zoomAt(area, [sourceNode, targetNode]);

      const graph = createFlowGraphQueries(editor.getNodes(), editor.getConnections());
      const candidates = graph
        .outgoingConnections(sourceNode.id)
        .filter((conn) => conn.target === targetNode.id);
      const connection =
        candidates.find((conn) => !ref.sourcePin || conn.sourceOutput === ref.sourcePin) ??
        candidates[0];

      if (!connection) {
        return;
      }

      const view = area.connectionViews.get(connection.id);
      if (view) {
        highlightConnectionEl(view.element as HTMLElement);
      }
    },

    navigateToJumps(hubDbId: number): void {
      const hubNode = nodeMap.get(hubDbId);
      if (!hubNode) {
        return;
      }

      const hubId = hubNode.nodeData?.hub_id;
      if (!hubId) {
        return;
      }

      const jumps = findJumpsForHub(nodeMap, hubId as string | number);
      if (jumps.length === 0) {
        return;
      }

      const allNodes = [hubNode, ...jumps.map((j) => j.reteNode)];
      AreaExtensions.zoomAt(area, allNodes);

      const jumpReteIds = jumps.map((j) => j.reteNode.id);
      highlightNodes(jumpReteIds, nodeColor(hubNode));
    },

    clearHighlights,

    destroy(): void {
      clearHighlights();
    },
  };
}
