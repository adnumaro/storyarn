/**
 * Mini-map navigation overlay for the map canvas.
 *
 * Shows a small overview of the full map in a corner, with a rectangle
 * indicating the current viewport. Click on the minimap to pan the main view.
 */

import L from "leaflet";
import { createElement, LayoutGrid, Maximize } from "lucide";
import { imageBounds } from "./coordinate_utils.js";

const MINIMAP_WIDTH = 180;
const MINIMAP_HEIGHT = 130;

/**
 * Creates the minimap attached to the hook instance.
 * @param {Object} hook - The SceneCanvas hook instance
 */
export function createMinimap(hook) {
  let container = null;
  let minimapMap = null;
  let viewportRect = null;
  let collapsed = true;

  function init() {
    createContainer();
    if (!collapsed) {
      buildMinimap();
    }
  }

  function destroy() {
    hook.leafletMap.off("moveend zoomend", updateViewport);
    if (minimapMap) {
      minimapMap.remove();
      minimapMap = null;
    }
    if (container?.parentNode) {
      container.parentNode.removeChild(container);
    }
    container = null;
  }

  /** Creates the minimap DOM container. */
  function createContainer() {
    container = document.createElement("div");
    container.className = "map-minimap";
    container.style.cssText = `
      position: absolute;
      bottom: 52px;
      right: 12px;
      z-index: 1000;
    `;

    // Button row (reset zoom + minimap toggle)
    const btnRow = document.createElement("div");
    btnRow.style.cssText = "display: flex; gap: 4px; justify-content: flex-end;";

    // Reset zoom button
    const resetBtn = document.createElement("button");
    resetBtn.className = "map-minimap-toggle";
    resetBtn.type = "button";
    resetBtn.title = "Reset zoom";
    resetBtn.appendChild(createElement(Maximize, { width: 14, height: 14 }));
    resetBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      if (hook.initialBounds) {
        hook.leafletMap.fitBounds(hook.initialBounds);
      }
    });
    btnRow.appendChild(resetBtn);

    // Toggle minimap button
    const toggleBtn = document.createElement("button");
    toggleBtn.className = "map-minimap-toggle";
    toggleBtn.type = "button";
    toggleBtn.title = "Toggle minimap";
    toggleBtn.appendChild(createElement(LayoutGrid, { width: 14, height: 14 }));
    toggleBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      toggle();
    });
    btnRow.appendChild(toggleBtn);

    container.appendChild(btnRow);

    // Map container (hidden when collapsed)
    const mapContainer = document.createElement("div");
    mapContainer.className = "map-miniscene-canvas";
    mapContainer.style.cssText = `
      width: ${MINIMAP_WIDTH}px;
      height: ${MINIMAP_HEIGHT}px;
      display: ${collapsed ? "none" : "block"};
    `;
    mapContainer.id = `miniscene-canvas-${Date.now()}`;
    container.appendChild(mapContainer);

    hook.el.appendChild(container);
  }

  /** Toggles the minimap open/closed. */
  function toggle() {
    collapsed = !collapsed;
    const canvas = container.querySelector(".map-miniscene-canvas");

    if (collapsed) {
      canvas.style.display = "none";
      hook.leafletMap.off("moveend zoomend", updateViewport);
      if (minimapMap) {
        minimapMap.remove();
        minimapMap = null;
        viewportRect = null;
      }
    } else {
      canvas.style.display = "block";
      buildMinimap();
    }
  }

  /** Builds the minimap Leaflet instance. */
  function buildMinimap() {
    const canvas = container.querySelector(".map-miniscene-canvas");
    if (!canvas || minimapMap) return;

    const w = hook.canvasWidth;
    const h = hook.canvasHeight;
    const bounds = imageBounds(w, h);

    minimapMap = L.map(canvas, {
      crs: L.CRS.Simple,
      zoomControl: false,
      attributionControl: false,
      dragging: false,
      scrollWheelZoom: false,
      doubleClickZoom: false,
      boxZoom: false,
      keyboard: false,
      touchZoom: false,
    });

    minimapMap.fitBounds(bounds);

    // Add background or placeholder
    if (hook.sceneData.background_url) {
      L.imageOverlay(hook.sceneData.background_url, bounds).addTo(minimapMap);
    } else {
      L.rectangle(bounds, {
        className: "map-grid-fill",
        weight: 1,
        fill: true,
        fillOpacity: 1,
        interactive: false,
      }).addTo(minimapMap);
    }

    // Viewport rectangle
    viewportRect = L.rectangle(hook.leafletMap.getBounds(), {
      color: "#ef4444",
      weight: 2,
      fill: true,
      fillColor: "#ef4444",
      fillOpacity: 0.15,
      interactive: false,
    }).addTo(minimapMap);

    // Click on minimap → pan main map
    minimapMap.on("click", (e) => {
      hook.leafletMap.panTo(e.latlng);
    });

    // Listen to main map movement → update viewport rect
    hook.leafletMap.on("moveend zoomend", updateViewport);

    // Initial update
    updateViewport();
  }

  /** Updates the viewport rectangle to match the main map's current bounds. */
  function updateViewport() {
    if (!viewportRect || !minimapMap) return;
    viewportRect.setBounds(hook.leafletMap.getBounds());
  }

  /** Called when background changes to update the minimap. */
  function refreshBackground() {
    if (!minimapMap || collapsed) return;
    // Rebuild the minimap to reflect new background
    minimapMap.remove();
    minimapMap = null;
    viewportRect = null;
    buildMinimap();
  }

  return {
    init,
    destroy,
    refreshBackground,
  };
}
