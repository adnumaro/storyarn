/**
 * Math utilities for magnetic connection detection.
 * Based on Rete.js magnetic-connection example (MIT License).
 */

/**
 * Find the nearest point to a target within a maximum distance.
 * @param {Array<{x: number, y: number}>} points
 * @param {{x: number, y: number}} target
 * @param {number} maxDistance
 * @returns {Object|undefined}
 */
export function findNearestPoint(points, target, maxDistance) {
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
export function isInsideRect(rect, point, margin) {
  return (
    point.y > rect.top - margin &&
    point.x > rect.left - margin &&
    point.x < rect.right + margin &&
    point.y < rect.bottom + margin
  );
}
