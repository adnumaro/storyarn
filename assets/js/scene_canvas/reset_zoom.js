/**
 * Reset-zoom button for the map canvas.
 *
 * Positions a single button in the bottom-right corner that fits the
 * map back to its initial bounds.
 */

import { createElement, Maximize } from "lucide";

/**
 * Creates the reset-zoom button attached to the hook instance.
 * @param {Object} hook - The SceneCanvas hook instance
 */
export function createResetZoomButton(hook) {
  const btn = document.createElement("button");
  btn.className = "map-minimap-toggle";
  btn.type = "button";
  btn.title = "Reset zoom";
  btn.appendChild(createElement(Maximize, { width: 14, height: 14 }));

  btn.addEventListener("click", (e) => {
    e.stopPropagation();
    if (hook.initialBounds) {
      hook.leafletMap.fitBounds(hook.initialBounds);
    }
  });

  // Append into the controls slot (flex row with legend), or fall back to canvas
  const slot = document.getElementById("scene-controls-slot");
  if (slot) {
    slot.appendChild(btn);
  } else {
    btn.style.cssText = "position: absolute; bottom: 12px; right: 12px; z-index: 1000;";
    hook.el.appendChild(btn);
  }

  return {
    destroy() {
      btn.remove();
    },
  };
}
