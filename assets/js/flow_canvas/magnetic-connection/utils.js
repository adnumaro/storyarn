/**
 * Utility functions for magnetic connection.
 * Based on Rete.js magnetic-connection example (MIT License).
 */

/**
 * Get bounding rect of a node from its data and view.
 * @param {Object} node - Node instance (must have width/height)
 * @param {Object} view - NodeView from area.nodeViews
 * @returns {{left: number, top: number, right: number, bottom: number}}
 */
export function getNodeRect(node, view) {
  const { x, y } = view.position;

  return {
    left: x,
    top: y,
    right: x + (node.width || 200),
    bottom: y + (node.height || 100),
  };
}
