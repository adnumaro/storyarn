/**
 * Debug composable for the flow debugger visual feedback.
 *
 * Manages CSS classes on node elements to show debug state:
 * - `.debug-current`  -- pulsing highlight on the node being evaluated
 * - `.debug-visited`  -- subtle border on already-visited nodes
 * - `.debug-waiting`  -- amber pulse when waiting for user input
 * - `.debug-error`    -- red indicator when node caused an error
 *
 * Connection highlighting uses CSS custom properties on the connection
 * view wrapper div. These properties inherit through Shadow DOM boundaries
 * into connection styles.
 *
 * Also handles auto-scrolling to the current node on each step.
 */

import { AreaExtensions, type AreaPlugin } from "rete-area-plugin";
import type { NodeEditor } from "rete";
import type { FlowNode } from "../lib/flow-node";
import type { FlowSchemes, FlowAreaExtra } from "../lib/rete-schemes";

export interface DebugHighlightNodeData {
  node_id: number;
  status: string;
  execution_path: number[];
}

export interface DebugHighlightConnectionsData {
  active_connection: {
    source_node_id: number;
    target_node_id: number;
    source_pin: string;
  } | null;
  execution_path: number[];
}

export interface DebugUpdateBreakpointsData {
  breakpoint_ids: number[];
}

export interface DebugHandler {
  init(): void;
  handleHighlightNode(data: DebugHighlightNodeData): void;
  handleHighlightConnections(data: DebugHighlightConnectionsData): void;
  handleClearHighlights(): void;
  handleUpdateBreakpoints(data: DebugUpdateBreakpointsData): void;
  destroy(): void;
}

/**
 * Finds the node DOM element for a given Rete node ID via area's nodeViews.
 * Uses a cache for fast repeated lookups.
 */
function findNodeElement(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  reteId: string,
  cache: Map<string, HTMLElement>,
): HTMLElement | null {
  const el = cache.get(reteId);
  if (el?.isConnected) {
    return el;
  }

  const view = area.nodeViews.get(reteId);
  if (!view) {
    return null;
  }

  const nodeEl = view.element.querySelector("[data-testid='node']") as HTMLElement | null;
  if (nodeEl) {
    cache.set(reteId, nodeEl);
  }
  return nodeEl;
}

/**
 * Finds the connection view wrapper element for a connection between two DB node IDs.
 * Returns view.element (the outer div) where CSS custom properties can be set.
 */
function findConnectionViewElement(
  editor: NodeEditor<FlowSchemes>,
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  sourceDbId: number,
  targetDbId: number,
): HTMLElement | null {
  for (const conn of editor.getConnections()) {
    const srcNode = editor.getNode(conn.source);
    const tgtNode = editor.getNode(conn.target);

    if (srcNode?.nodeId === sourceDbId && tgtNode?.nodeId === targetDbId) {
      const view = area.connectionViews.get(conn.id);
      if (view) {
        return view.element;
      }
    }
  }
  return null;
}

/**
 * Sets CSS custom properties for the "active" debug state on a connection view element.
 */
function setConnActiveProps(viewEl: HTMLElement): void {
  viewEl.style.setProperty("--conn-stroke", "var(--color-primary, #7c3aed)");
  viewEl.style.setProperty("--conn-stroke-width", "3px");
  viewEl.style.setProperty("--conn-dash", "8 4");
  viewEl.style.setProperty("--conn-animation", "debug-flow 0.6s linear infinite");
}

/**
 * Sets CSS custom properties for the "visited" debug state on a connection view element.
 */
function setConnVisitedProps(viewEl: HTMLElement): void {
  viewEl.style.setProperty(
    "--conn-stroke",
    "color-mix(in oklch, var(--color-primary, #7c3aed) 30%, transparent)",
  );
  viewEl.style.setProperty("--conn-stroke-width", "2px");
  viewEl.style.removeProperty("--conn-dash");
  viewEl.style.removeProperty("--conn-animation");
}

/**
 * Removes all debug CSS custom properties from a connection view element.
 */
function clearConnDebugProps(viewEl: HTMLElement): void {
  viewEl.style.removeProperty("--conn-stroke");
  viewEl.style.removeProperty("--conn-stroke-width");
  viewEl.style.removeProperty("--conn-dash");
  viewEl.style.removeProperty("--conn-animation");
}

/**
 * Creates the debug composable with methods bound to the Rete instances.
 */
export function debug(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  editor: NodeEditor<FlowSchemes>,
  nodeMap: Map<string | number, FlowNode>,
  _handleEvent: unknown,
): DebugHandler {
  let currentEl: HTMLElement | null = null;
  let visitedEls = new Set<HTMLElement>();
  let breakpointEls = new Set<HTMLElement>();
  let activeConnView: HTMLElement | null = null;
  let visitedConnViews = new Set<HTMLElement>();
  const nodeElCache = new Map<string, HTMLElement>();
  let lastPathLength = 0;

  function init(): void {
    // No-op for now; available for future setup logic.
  }

  function handleHighlightNode(data: DebugHighlightNodeData): void {
    const { node_id, status, execution_path } = data;

    // 1. Remove previous "current" highlight
    if (currentEl) {
      currentEl.classList.remove("debug-current", "debug-waiting", "debug-error");
      // Keep debug-visited on it since it was visited
      currentEl.classList.add("debug-visited");
    }

    // 2. Mark only NEW nodes in execution path as visited (skip already-processed)
    const path = execution_path || [];
    for (let i = lastPathLength; i < path.length; i++) {
      const dbId = path[i];
      const reteNode = nodeMap.get(dbId);
      if (!reteNode) {
        continue;
      }

      const el = findNodeElement(area, reteNode.id, nodeElCache);
      if (!el || visitedEls.has(el)) {
        continue;
      }

      el.classList.add("debug-visited");
      visitedEls.add(el);
    }
    lastPathLength = path.length;

    // 3. Highlight current node
    const currentNode = nodeMap.get(node_id);
    if (!currentNode) {
      return;
    }

    const el = findNodeElement(area, currentNode.id, nodeElCache);
    if (!el) {
      return;
    }

    // Remove visited style on current (current takes precedence)
    el.classList.remove("debug-visited");

    if (status === "waiting_input") {
      el.classList.add("debug-waiting");
    } else if (status === "error") {
      el.classList.add("debug-error");
    } else {
      el.classList.add("debug-current");
    }

    currentEl = el;
    visitedEls.add(el);

    // 4. Scroll canvas to center on current node
    AreaExtensions.zoomAt(area, [currentNode], { scale: undefined });
  }

  function handleHighlightConnections(data: DebugHighlightConnectionsData): void {
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
        const viewEl = findConnectionViewElement(
          editor,
          area,
          execution_path[i],
          execution_path[i + 1],
        );
        if (viewEl && !visitedConnViews.has(viewEl)) {
          setConnVisitedProps(viewEl);
          visitedConnViews.add(viewEl);
        }
      }
    }

    // 3. Highlight current active connection
    if (active_connection) {
      const viewEl = findConnectionViewElement(
        editor,
        area,
        active_connection.source_node_id,
        active_connection.target_node_id,
      );
      if (viewEl) {
        clearConnDebugProps(viewEl);
        setConnActiveProps(viewEl);
        activeConnView = viewEl;
      }
    }
  }

  function handleUpdateBreakpoints(data: DebugUpdateBreakpointsData): void {
    const { breakpoint_ids } = data;
    const idSet = new Set(breakpoint_ids || []);

    // Remove class from nodes no longer in breakpoints
    for (const el of breakpointEls) {
      el.classList.remove("debug-breakpoint");
    }
    breakpointEls = new Set();

    // Add class to current breakpoint nodes
    for (const dbId of idSet) {
      const reteNode = nodeMap.get(dbId);
      if (!reteNode) {
        continue;
      }

      const el = findNodeElement(area, reteNode.id, nodeElCache);
      if (!el) {
        continue;
      }

      el.classList.add("debug-breakpoint");
      breakpointEls.add(el);
    }
  }

  function handleClearHighlights(): void {
    // Clear current node
    if (currentEl) {
      currentEl.classList.remove("debug-current", "debug-waiting", "debug-error");
      currentEl = null;
    }

    // Clear all visited nodes
    for (const el of visitedEls) {
      el.classList.remove("debug-visited", "debug-current", "debug-waiting", "debug-error");
    }
    visitedEls = new Set();

    // Clear breakpoint indicators
    for (const el of breakpointEls) {
      el.classList.remove("debug-breakpoint");
    }
    breakpointEls = new Set();

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

    // Reset caches
    nodeElCache.clear();
    lastPathLength = 0;
  }

  function destroy(): void {
    handleClearHighlights();
  }

  return {
    init,
    handleHighlightNode,
    handleHighlightConnections,
    handleClearHighlights,
    handleUpdateBreakpoints,
    destroy,
  };
}
