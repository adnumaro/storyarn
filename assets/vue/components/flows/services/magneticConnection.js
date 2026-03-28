/**
 * Magnetic connection for Rete.js — enlarges the connection dropping area
 * so users don't need to aim precisely at sockets.
 *
 * Based on Rete.js magnetic-connection example (MIT License).
 * Self-contained composable with inlined math/utils helpers.
 */

import { AreaPlugin } from "rete-area-plugin";
import { createPseudoconnection } from "rete-connection-plugin";
import { getElementCenter } from "rete-render-utils";

// -- Inlined from math.js --

/**
 * Find the nearest point to a target within a maximum distance.
 * @param {Array<{x: number, y: number}>} points
 * @param {{x: number, y: number}} target
 * @param {number} maxDistance
 * @returns {Object|undefined}
 */
function findNearestPoint(points, target, maxDistance) {
  const result = points.reduce((nearest, point) => {
    const dist = Math.sqrt((point.x - target.x) ** 2 + (point.y - target.y) ** 2);

    if (dist > maxDistance) return nearest;
    if (nearest === null || dist < nearest.distance) return { point, distance: dist };
    return nearest;
  }, null);

  return result?.point;
}

/**
 * Check if a point is inside a rect (with margin).
 * @param {{left: number, top: number, right: number, bottom: number}} rect
 * @param {{x: number, y: number}} point
 * @param {number} margin
 * @returns {boolean}
 */
function isInsideRect(rect, point, margin) {
  return (
    point.y > rect.top - margin &&
    point.x > rect.left - margin &&
    point.x < rect.right + margin &&
    point.y < rect.bottom + margin
  );
}

// -- Inlined from utils.js --

/**
 * Get bounding rect of a node from its data and view.
 * @param {Object} node - Node instance (must have width/height)
 * @param {Object} view - NodeView from area.nodeViews
 * @returns {{left: number, top: number, right: number, bottom: number}}
 */
function getNodeRect(node, view) {
  const { x, y } = view.position;

  return {
    left: x,
    top: y,
    right: x + (node.width || 200),
    bottom: y + (node.height || 100),
  };
}

// -- Composable --

/**
 * Enables magnetic connection behavior on a ConnectionPlugin.
 *
 * When a user drags a connection, this detects nearby sockets and snaps
 * the connection to the nearest valid socket within range.
 *
 * @param {import("rete-connection-plugin").ConnectionPlugin} connection
 * @param {Object} props
 * @param {Function} props.createConnection - (from, to) => Promise<void>
 * @param {Function} props.display - (from, to) => boolean — whether to show magnetic indicator
 * @param {Function} props.offset - (socket, position) => {x, y} — visual offset for the snap
 * @param {number} [props.margin=50] - How far from a node to start looking for sockets
 * @param {number} [props.distance=50] - Maximum snap distance to a socket
 */
export function magneticConnection(connection, props) {
  const area = connection.parentScope(AreaPlugin);
  const editor = area.parentScope();
  const sockets = new Map();
  const magneticConnection = createPseudoconnection({ isMagnetic: true });

  const margin = props.margin ?? 50;
  const distance = props.distance ?? 50;

  let picked = null;
  let nearestSocket = null;

  connection.addPipe(async (context) => {
    if (!context || typeof context !== "object" || !("type" in context)) {
      return context;
    }

    if (context.type === "connectionpick") {
      picked = context.data.socket;
    } else if (context.type === "connectiondrop") {
      if (nearestSocket && !context.data.created) {
        await props.createConnection(context.data.initial, nearestSocket);
      }
      picked = null;
      magneticConnection.unmount(area);
    } else if (context.type === "pointermove") {
      if (!picked) return context;

      const point = context.data.position;
      const nodes = Array.from(area.nodeViews.entries());
      const socketsList = Array.from(sockets.values());

      // Find nodes near the cursor
      const rects = nodes.map(([id, view]) => ({
        id,
        ...getNodeRect(editor.getNode(id), view),
      }));
      const nearestRects = rects.filter((rect) => isInsideRect(rect, point, margin));
      const nearestNodeIds = nearestRects.map(({ id }) => id);

      // Get sockets belonging to nearby nodes
      const nearestSockets = socketsList.filter((item) => nearestNodeIds.includes(item.nodeId));

      // Calculate positions for those sockets
      const socketsPositions = await Promise.all(
        nearestSockets.map(async (socket) => {
          const nodeView = area.nodeViews.get(socket.nodeId);
          if (!nodeView) return null;

          const { x, y } = await getElementCenter(socket.element, nodeView.element);

          return {
            ...socket,
            x: x + nodeView.position.x,
            y: y + nodeView.position.y,
          };
        }),
      );

      // Find the nearest valid socket
      const validPositions = socketsPositions.filter(Boolean);
      nearestSocket = findNearestPoint(validPositions, point, distance) || null;

      if (nearestSocket && props.display(picked, nearestSocket)) {
        if (!magneticConnection.isMounted()) magneticConnection.mount(area);
        const { x, y } = nearestSocket;
        magneticConnection.render(area, props.offset(nearestSocket, { x, y }), picked);
      } else if (magneticConnection.isMounted()) {
        magneticConnection.unmount(area);
      }
    } else if (context.type === "render" && context.data.type === "socket") {
      // Track socket elements for position lookup
      sockets.set(context.data.element, context.data);
    } else if (context.type === "unmount") {
      sockets.delete(context.data.element);
    }

    return context;
  });
}
