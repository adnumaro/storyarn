/**
 * Node type configurations — thin re-export from per-type modules.
 *
 * Also provides the shared `createIconSvg` utility used by per-type modules.
 */

import { createElement } from "lucide";

/**
 * Creates an SVG string from a Lucide icon.
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
export { NODE_CONFIGS, getNodeDef } from "./nodes/index.js";
