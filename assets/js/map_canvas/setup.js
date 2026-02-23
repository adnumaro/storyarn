/**
 * Leaflet map initialization for the map canvas.
 *
 * Uses L.CRS.Simple (image-only, no geographic tiles).
 * If the map has a background asset, displays it as L.imageOverlay.
 * Otherwise shows a grid placeholder.
 */

import L from "leaflet";
import { imageBounds, toLatLng } from "./coordinate_utils.js";

// Default dimensions when map has no explicit size
const DEFAULT_WIDTH = 1000;
const DEFAULT_HEIGHT = 1000;

/**
 * Initializes the Leaflet map on the given container element.
 * @param {Object} hook - The MapCanvas hook instance
 * @returns {{ map: L.Map, width: number, height: number }}
 */
export function initMap(hook) {
  const container = hook.el.querySelector("#map-canvas-container");
  const data = hook.mapData;

  const width = data.width || DEFAULT_WIDTH;
  const height = data.height || DEFAULT_HEIGHT;
  const bounds = imageBounds(width, height);

  const map = L.map(container, {
    crs: L.CRS.Simple,
    minZoom: -3,
    maxZoom: 5,
    zoomSnap: 0.25,
    zoomDelta: 0.5,
    attributionControl: false,
  });

  // Background image or grid placeholder
  if (data.background_url) {
    hook.backgroundOverlay = L.imageOverlay(data.background_url, bounds).addTo(map);

    // If no explicit dimensions, use the image's intrinsic size once loaded
    if (!data.width || !data.height) {
      const img = new Image();
      img.onload = () => {
        const natW = img.naturalWidth;
        const natH = img.naturalHeight;
        if (natW && natH && (natW !== width || natH !== height)) {
          const newBounds = imageBounds(natW, natH);
          hook.backgroundOverlay.setBounds(newBounds);
          hook.canvasWidth = natW;
          hook.canvasHeight = natH;
          hook.initialBounds = newBounds;
          map.setMaxBounds(null);
          map.fitBounds(newBounds);

          // Reposition all elements that were placed with the old default dimensions
          if (hook.pinHandler) hook.pinHandler.repositionAll();
          if (hook.zoneHandler) hook.zoneHandler.repositionAll();
          if (hook.connectionHandler) hook.connectionHandler.repositionAll();
          if (hook.annotationHandler) hook.annotationHandler.repositionAll();
        }
      };
      img.src = data.background_url;
    }
  } else {
    hook.gridOverlay = addGridPlaceholder(map, width, height);
  }

  // Fit map view to image bounds
  map.fitBounds(bounds);

  // Set initial zoom if provided
  if (data.default_zoom && data.default_zoom !== 1.0) {
    map.setZoom(map.getZoom() * data.default_zoom);
  }

  // Store initial view for reset
  hook.initialBounds = bounds;

  // Custom pane for fog-of-war overlays — sits between the background
  // image (overlayPane, z-index 400) and element layers (shadowPane 500+),
  // so fog darkens the background but elements render above it.
  const fogPane = map.createPane("fogPane");
  fogPane.style.zIndex = 450;
  fogPane.style.pointerEvents = "none";

  // Boundary fog overlay — darkens area outside the parent zone polygon
  if (data.boundary_vertices && data.boundary_vertices.length >= 3) {
    addBoundaryFog(map, data.boundary_vertices, width, height);
  }

  // Layer groups for pins, zones, connections, and annotations
  hook.pinLayer = L.layerGroup().addTo(map);
  hook.zoneLayer = L.layerGroup().addTo(map);
  hook.connectionLayer = L.layerGroup().addTo(map);
  hook.annotationLayer = L.layerGroup().addTo(map);

  return { map, width, height };
}

/**
 * Draws a subtle grid when no background image is set.
 * Returns the created layer group for later removal.
 *
 * Colors are applied via CSS classes (map-grid-fill, map-grid-line) using
 * CSS variables, so they automatically adapt to light/dark theme changes
 * without needing JS color resolution.
 */
export function addGridPlaceholder(map, width, height) {
  const bounds = imageBounds(width, height);
  const gridSize = Math.max(width, height) / 10;

  const gridLines = [];

  // Vertical lines
  for (let x = 0; x <= width; x += gridSize) {
    gridLines.push([
      [0, x],
      [-height, x],
    ]);
  }

  // Horizontal lines
  for (let y = 0; y <= height; y += gridSize) {
    gridLines.push([
      [-y, 0],
      [-y, width],
    ]);
  }

  const group = L.layerGroup();

  // Border rectangle — colors overridden by .map-grid-fill CSS class
  L.rectangle(bounds, {
    className: "map-grid-fill",
    weight: 2,
    fill: true,
    fillOpacity: 1,
    interactive: false,
  }).addTo(group);

  // Grid lines — colors overridden by .map-grid-line CSS class
  L.polyline(gridLines, {
    className: "map-grid-line",
    weight: 1,
    interactive: false,
  }).addTo(group);

  group.addTo(map);
  return group;
}

/**
 * Renders a semi-transparent fog overlay outside the parent zone polygon.
 * Uses a polygon with a hole (evenodd fill-rule) so the interior of the
 * zone shape is transparent and everything outside is darkened.
 */
function addBoundaryFog(map, vertices, w, h) {
  // Outer ring: covers the entire canvas with a generous margin
  const margin = Math.max(w, h);
  const outerRing = [
    [margin, -margin],
    [margin, w + margin],
    [-h - margin, w + margin],
    [-h - margin, -margin],
  ];

  // Inner ring: the zone polygon in Leaflet coordinates (must be wound
  // in the opposite direction from the outer ring for evenodd to work)
  const innerRing = vertices.map((v) => {
    const ll = toLatLng(v.x, v.y, w, h);
    return [ll.lat, ll.lng];
  });

  L.polygon([outerRing, innerRing], {
    fillColor: "#000",
    fillOpacity: 0.35,
    stroke: true,
    color: "#6b7280",
    weight: 1.5,
    dashArray: "6, 4",
    interactive: false,
    pane: "fogPane",
  }).addTo(map);
}
