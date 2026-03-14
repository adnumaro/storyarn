/**
 * Zoom controls for the map canvas.
 *
 * Creates zoom in (+), zoom out (-), and reset (fit) buttons in the
 * bottom-right controls slot alongside the legend.
 */

import { createElement, Plus, Minus, Maximize } from "lucide";

/**
 * Creates zoom control buttons attached to the hook instance.
 * @param {Object} hook - The SceneCanvas hook instance
 */
export function createResetZoomButton(hook) {
  const group = document.createElement("div");
  group.className = "flex items-center gap-1";

  // Zoom in
  const zoomIn = makeButton("Zoom in", Plus, () => {
    hook.leafletMap.zoomIn();
  });

  // Zoom out
  const zoomOut = makeButton("Zoom out", Minus, () => {
    hook.leafletMap.zoomOut();
  });

  // Reset / fit bounds
  const reset = makeButton("Reset zoom", Maximize, () => {
    if (hook.initialBounds) {
      hook.leafletMap.fitBounds(hook.initialBounds);
    }
  });

  group.appendChild(zoomIn);
  group.appendChild(zoomOut);
  group.appendChild(reset);

  // Append into the controls slot (flex row with legend), or fall back to canvas
  const slot = document.getElementById("scene-controls-slot");
  if (slot) {
    slot.appendChild(group);
  } else {
    group.style.cssText = "position: absolute; bottom: 12px; right: 12px; z-index: 1000; display: flex; gap: 4px;";
    hook.el.appendChild(group);
  }

  return {
    destroy() {
      group.remove();
    },
  };
}

function makeButton(title, Icon, onClick) {
  const btn = document.createElement("button");
  btn.className = "map-minimap-toggle";
  btn.type = "button";
  btn.title = title;
  btn.appendChild(createElement(Icon, { width: 14, height: 14 }));

  btn.addEventListener("click", (e) => {
    e.stopPropagation();
    onClick();
  });

  return btn;
}
