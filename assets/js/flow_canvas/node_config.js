/**
 * Node type configurations — thin re-export from per-type modules.
 *
 * Icon utilities:
 * - createIconSvg(icon) — 16×16 node header icons (stroke styling)
 * - createIconHTML(icon, { size }) — general-purpose icon → outerHTML string
 */

import { createElement } from "lucide";

/**
 * Creates an SVG outerHTML string from a Lucide icon.
 * General-purpose: use for inline icons, indicators, nav links, etc.
 *
 * @param {object} icon - Lucide icon component (e.g. ArrowRight, Lock)
 * @param {object} [options]
 * @param {number} [options.size=10] - Icon width and height in px
 * @returns {string} SVG markup string
 */
export function createIconHTML(icon, { size = 10 } = {}) {
  return createElement(icon, { width: size, height: size }).outerHTML;
}

/**
 * Creates an SVG string for node headers (16×16, with stroke styling).
 * @param {object} icon - Lucide icon component
 * @returns {string} SVG markup string
 */
export function createIconSvg(icon) {
  const el = createElement(icon, {
    width: 16,
    height: 16,
    stroke: "currentColor",
    "stroke-width": 2,
  });
  return el.outerHTML;
}

// Re-export from the per-type registry
export { getNodeDef, NODE_CONFIGS } from "./nodes/index.js";
