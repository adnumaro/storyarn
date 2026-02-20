/**
 * Shape preset vertex generators for the map canvas.
 *
 * Each function takes a center point (cx, cy) in percentage coordinates (0-100)
 * and returns an array of {x, y} vertices, clamped to the [0, 100] range.
 */

const RECT_W = 20;
const RECT_H = 15;
const TRI_W = 20;
const TRI_H = 17;
const CIRCLE_RADIUS = 10;
const CIRCLE_SIDES = 16;

function clamp(val) {
  return Math.min(100, Math.max(0, val));
}

function round2(val) {
  return Math.round(val * 100) / 100;
}

/**
 * Rectangle vertices centered on (cx, cy). 20x15 units.
 */
export function rectangleVertices(cx, cy) {
  const hw = RECT_W / 2;
  const hh = RECT_H / 2;
  return [
    { x: round2(clamp(cx - hw)), y: round2(clamp(cy - hh)) },
    { x: round2(clamp(cx + hw)), y: round2(clamp(cy - hh)) },
    { x: round2(clamp(cx + hw)), y: round2(clamp(cy + hh)) },
    { x: round2(clamp(cx - hw)), y: round2(clamp(cy + hh)) },
  ];
}

/**
 * Triangle vertices centered on (cx, cy). 20x17 units.
 */
export function triangleVertices(cx, cy) {
  const hw = TRI_W / 2;
  const hh = TRI_H / 2;
  return [
    { x: round2(clamp(cx)), y: round2(clamp(cy - hh)) },
    { x: round2(clamp(cx + hw)), y: round2(clamp(cy + hh)) },
    { x: round2(clamp(cx - hw)), y: round2(clamp(cy + hh)) },
  ];
}

/**
 * Circle vertices (regular polygon) centered on (cx, cy). Radius 10 units.
 * Compensates for non-square maps so the shape appears circular on screen.
 * @param {number} cx - Center X (0-100)
 * @param {number} cy - Center Y (0-100)
 * @param {number} [sides=16] - Number of sides
 * @param {number} [aspectRatio=1] - Map width / height
 */
export function circleVertices(cx, cy, sides = CIRCLE_SIDES, aspectRatio = 1) {
  const radiusX = CIRCLE_RADIUS;
  const radiusY = CIRCLE_RADIUS * aspectRatio;
  return Array.from({ length: sides }, (_, i) => {
    const angle = (i / sides) * 2 * Math.PI - Math.PI / 2; // start from top
    return {
      x: round2(clamp(cx + radiusX * Math.cos(angle))),
      y: round2(clamp(cy + radiusY * Math.sin(angle))),
    };
  });
}

/**
 * Returns the vertex generator for a given shape tool name.
 * @param {string} tool - "rectangle" | "triangle" | "circle"
 * @returns {Function|null}
 */
export function getShapePreset(tool) {
  switch (tool) {
    case "rectangle":
      return rectangleVertices;
    case "triangle":
      return triangleVertices;
    case "circle":
      return circleVertices;
    default:
      return null;
  }
}
