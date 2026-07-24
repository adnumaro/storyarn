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

/**
 * Evidence-highlight styling. Deliberately its OWN layer of custom properties:
 * FlowConnection.vue resolves --conn-evidence-* over the debug panel's
 * --conn-* variables, so an expiring evidence highlight cannot wipe an active
 * debug highlight (and vice versa).
 */
const CONN_EVIDENCE_PROPS: Record<string, string> = {
  "--conn-evidence-stroke": "var(--color-primary, #7c3aed)",
  "--conn-evidence-stroke-width": "3px",
  "--conn-evidence-dash": "8 4",
  "--conn-evidence-animation": "debug-flow 0.6s linear infinite",
};

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
      for (const prop of Object.keys(CONN_EVIDENCE_PROPS)) {
        highlightedConnectionEl.style.removeProperty(prop);
      }
      highlightedConnectionEl = null;
    }
  }

  // Finding-evidence highlight with auto-clear, on its own styling layer so a
  // running debug session keeps its own connection styling.
  function highlightConnectionEl(viewEl: HTMLElement): void {
    clearHighlights();
    for (const [prop, value] of Object.entries(CONN_EVIDENCE_PROPS)) {
      viewEl.style.setProperty(prop, value);
    }
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

      const graph = createFlowGraphQueries(editor.getNodes(), editor.getConnections());
      // Only the exact pin pair identifies the evidence: parallel connections
      // between the same node pair differ by pin, so a laxer match would
      // highlight a DIFFERENT edge than the finding is about.
      const connection = graph
        .outgoingConnections(sourceNode.id)
        .find(
          (conn) =>
            conn.target === targetNode.id &&
            (!ref.sourcePin || conn.sourceOutput === ref.sourcePin) &&
            (!ref.targetPin || conn.targetInput === ref.targetPin),
        );

      const view = connection ? area.connectionViews.get(connection.id) : undefined;

      AreaExtensions.zoomAt(area, [sourceNode, targetNode]);

      if (view) {
        highlightConnectionEl(view.element as HTMLElement);
      } else {
        // The edge has no rendered geometry — a source pin that no longer
        // exists has no socket to draw from, which is precisely what these
        // findings report. Point at both endpoints (evidence of the same
        // finding) rather than at some other edge between them.
        highlightNodes([sourceNode.id, targetNode.id], nodeColor(sourceNode));
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
