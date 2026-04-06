/**
 * Magnetic connection for Rete.js -- enlarges the connection dropping area
 * so users don't need to aim precisely at sockets.
 *
 * Based on Rete.js magnetic-connection example (MIT License).
 * Self-contained composable with inlined math/utils helpers.
 */

import { AreaPlugin } from "rete-area-plugin";
import {
  type ConnectionPlugin,
  createPseudoconnection,
  type SocketData,
} from "rete-connection-plugin";
import { getElementCenter } from "rete-render-utils";
import type { FlowSchemes, FlowAreaExtra } from "../lib/rete-schemes";

// -- Inlined from math.js --

interface Point {
  x: number;
  y: number;
}

interface PointWithDistance extends Point {
  distance: number;
}

interface Rect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

interface NodeRect extends Rect {
  id: string;
}

/**
 * Find the nearest point to a target within a maximum distance.
 */
function findNearestPoint(
  points: (SocketData & Point)[],
  target: Point,
  maxDistance: number,
): (SocketData & Point) | undefined {
  const result = points.reduce<(PointWithDistance & SocketData) | null>((nearest, point) => {
    const dist = Math.sqrt((point.x - target.x) ** 2 + (point.y - target.y) ** 2);

    if (dist > maxDistance) {
      return nearest;
    }
    if (nearest === null || dist < nearest.distance) {
      return { ...point, distance: dist };
    }
    return nearest;
  }, null);

  return result || undefined;
}

/**
 * Check if a point is inside a rect (with margin).
 */
function isInsideRect(rect: Rect, point: Point, margin: number): boolean {
  return (
    point.y > rect.top - margin &&
    point.x > rect.left - margin &&
    point.x < rect.right + margin &&
    point.y < rect.bottom + margin
  );
}

// -- Inlined from utils.js --

interface NodeWithSize {
  width?: number;
  height?: number;
}

interface NodeView {
  position: Point;
  element: HTMLElement;
}

/**
 * Get bounding rect of a node from its data and view.
 */
function getNodeRect(node: NodeWithSize, view: NodeView): Rect {
  const { x, y } = view.position;

  return {
    left: x,
    top: y,
    right: x + (node.width || 200),
    bottom: y + (node.height || 100),
  };
}

// -- Composable --

export interface MagneticConnectionProps {
  createConnection: (from: SocketData, to: SocketData) => Promise<void>;
  display: (from: SocketData, to: SocketData) => boolean;
  offset: (socket: SocketData, position: Point) => Point;
  margin?: number;
  distance?: number;
}

/**
 * Enables magnetic connection behavior on a ConnectionPlugin.
 *
 * When a user drags a connection, this detects nearby sockets and snaps
 * the connection to the nearest valid socket within range.
 */
export function magneticConnection(
  connection: ConnectionPlugin<FlowSchemes>,
  props: MagneticConnectionProps,
): void {
  // Rete.js parentScope() returns a generic Scope type; cast needed for typed plugin access
  const area = connection.parentScope(AreaPlugin) as unknown as AreaPlugin<
    FlowSchemes,
    FlowAreaExtra
  >;
  const editor = area.parentScope() as unknown as import("rete").NodeEditor<FlowSchemes>;
  const sockets = new Map<HTMLElement, SocketData>();
  const pseudoconn = createPseudoconnection({ isMagnetic: true } as never);

  const margin = props.margin ?? 50;
  const distance = props.distance ?? 50;

  let picked: SocketData | null = null;
  let nearestSocket: (SocketData & Point) | null = null;

  function handleConnectionPick(context: unknown): void {
    picked = (context as { data: { socket: SocketData } }).data.socket;
  }

  async function handleConnectionDrop(context: unknown): Promise<void> {
    const dropData = (context as { data: { initial: SocketData; created: boolean } }).data;
    if (nearestSocket && !dropData.created) {
      await props.createConnection(dropData.initial, nearestSocket);
    }
    picked = null;
    pseudoconn.unmount(area);
  }

  async function handlePointerMove(context: unknown): Promise<void> {
    const point = (context as { data: { position: Point } }).data.position;
    const nodes = Array.from(area.nodeViews.entries());
    const socketsList = Array.from(sockets.values());

    const rects: NodeRect[] = nodes.map(([id, view]) => ({
      id,
      ...getNodeRect(editor.getNode(id) as NodeWithSize, view as unknown as NodeView),
    }));
    const nearestRects = rects.filter((rect) => isInsideRect(rect, point, margin));
    const nearestNodeIds = nearestRects.map(({ id }) => id);

    const nearestSockets = socketsList.filter((item) => nearestNodeIds.includes(item.nodeId));

    const socketsPositions = await Promise.all(
      nearestSockets.map(async (socket) => {
        const nodeView = area.nodeViews.get(socket.nodeId);
        if (!nodeView) return null;

        const { x, y } = await getElementCenter(
          socket.element,
          (nodeView as unknown as NodeView).element,
        );

        return {
          ...socket,
          x: x + (nodeView as unknown as NodeView).position.x,
          y: y + (nodeView as unknown as NodeView).position.y,
        };
      }),
    );

    const validPositions = socketsPositions.filter((p): p is SocketData & Point => p !== null);
    nearestSocket = findNearestPoint(validPositions, point, distance) || null;

    if (nearestSocket && picked && props.display(picked, nearestSocket)) {
      if (!pseudoconn.isMounted()) pseudoconn.mount(area);
      const { x, y } = nearestSocket;
      pseudoconn.render(area, props.offset(nearestSocket, { x, y }), picked);
    } else if (pseudoconn.isMounted()) {
      pseudoconn.unmount(area);
    }
  }

  function handleSocketRender(context: unknown): void {
    const socketData = (context as { data: SocketData }).data;
    sockets.set(socketData.element, socketData);
  }

  function isValidPipeContext(context: unknown): context is { type: string } {
    return !!context && typeof context === "object" && "type" in context;
  }

  function isSocketRender(context: { type: string }): boolean {
    return context.type === "render" && (context as unknown as { data: { type: string } }).data.type === "socket";
  }

  async function dispatchPipeEvent(context: { type: string }): Promise<void> {
    if (context.type === "connectionpick") {
      handleConnectionPick(context);
    } else if (context.type === "connectiondrop") {
      await handleConnectionDrop(context);
    } else if (context.type === "pointermove" && picked) {
      await handlePointerMove(context);
    } else if (isSocketRender(context)) {
      handleSocketRender(context);
    } else if (context.type === "unmount") {
      sockets.delete((context as unknown as { data: { element: HTMLElement } }).data.element);
    }
  }

  connection.addPipe(async (context) => {
    if (isValidPipeContext(context)) {
      await dispatchPipeEvent(context);
    }
    return context;
  });
}
