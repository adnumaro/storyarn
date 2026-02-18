/**
 * Leaflet map initialization for the map canvas.
 *
 * Uses L.CRS.Simple (image-only, no geographic tiles).
 * If the map has a background asset, displays it as L.imageOverlay.
 * Otherwise shows a grid placeholder.
 */

import L from "leaflet";
import { imageBounds } from "./coordinate_utils.js";

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
 */
export function addGridPlaceholder(map, width, height) {
  const bounds = imageBounds(width, height);
  const gridSize = Math.max(width, height) / 10;

  const gridLines = [];

  // Vertical lines
  for (let x = 0; x <= width; x += gridSize) {
    gridLines.push([[0, x], [-height, x]]);
  }

  // Horizontal lines
  for (let y = 0; y <= height; y += gridSize) {
    gridLines.push([[-y, 0], [-y, width]]);
  }

  const group = L.layerGroup();

  // Border rectangle (drawn first so grid lines render on top)
  L.rectangle(bounds, {
    color: "#9ca3af",
    weight: 2,
    fill: true,
    fillColor: "#f9fafb",
    fillOpacity: 1,
    interactive: false,
  }).addTo(group);

  L.polyline(gridLines, {
    color: "#d1d5db",
    weight: 1,
    opacity: 0.5,
    interactive: false,
  }).addTo(group);

  group.addTo(map);
  return group;
}
