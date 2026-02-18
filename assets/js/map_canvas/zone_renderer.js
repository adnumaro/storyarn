/**
 * Zone rendering utilities for the map canvas.
 *
 * Creates Leaflet polygons styled with fill/border colors, opacity, and dash patterns.
 */

import L from "leaflet";
import { toLatLng } from "./coordinate_utils.js";

const DEFAULT_FILL_COLOR = "#3b82f6";
const DEFAULT_BORDER_COLOR = "#1e40af";
const SELECTED_BORDER_WEIGHT = 4;

// border_style → Leaflet dashArray mapping
const DASH_PATTERNS = {
  solid: null,
  dashed: "10, 6",
  dotted: "3, 6",
};

/**
 * Creates a Leaflet polygon for a zone.
 * @param {Object} zone - Zone data from server
 * @param {number} w - Canvas width
 * @param {number} h - Canvas height
 * @returns {L.Polygon}
 */
export function createZonePolygon(zone, w, h) {
  const latLngs = verticesToLatLngs(zone.vertices, w, h);

  const polygon = L.polygon(latLngs, buildZoneStyle(zone));

  // Store zone data on the polygon for easy access
  polygon.zoneData = zone;

  return polygon;
}

/**
 * Updates a polygon's style to reflect changed zone data.
 */
export function updateZonePolygon(polygon, zone) {
  polygon.zoneData = zone;
  polygon.setStyle(buildZoneStyle(zone));

  // Update vertices if they changed
  if (zone.vertices) {
    // We need w/h but can extract from existing latLngs ratio — not ideal.
    // Instead, the caller should pass w/h or we store them on polygon.
    // For now, style-only update is the common case.
  }
}

/**
 * Updates a polygon's vertices (for vertex editing).
 */
export function updateZoneVertices(polygon, vertices, w, h) {
  const latLngs = verticesToLatLngs(vertices, w, h);
  polygon.setLatLngs(latLngs);
}

/**
 * Adds or removes selected styling on a zone polygon.
 */
export function setZoneSelected(polygon, selected) {
  polygon._selected = selected;

  if (selected) {
    polygon.setStyle({
      weight: SELECTED_BORDER_WEIGHT,
      dashArray: null,
    });
  } else {
    const zone = polygon.zoneData;
    polygon.setStyle({
      weight: zone.border_width || 2,
      dashArray: DASH_PATTERNS[zone.border_style] || null,
      fillOpacity: zone.opacity != null ? zone.opacity : 0.3,
    });
  }
}

/**
 * Creates a non-interactive label marker at the polygon centroid.
 * Returns null when zone has no name.
 *
 * Uses textContent (not innerHTML) to avoid XSS with user-provided zone names.
 */
export function createZoneLabelMarker(zone, w, h) {
  if (!zone.name) return null;

  const center = computeCentroid(zone.vertices, w, h);
  const span = document.createElement("span");
  span.textContent = zone.name;

  return L.marker(center, {
    icon: L.divIcon({
      className: "map-zone-label",
      html: span.outerHTML,
      iconSize: null,
      iconAnchor: null,
    }),
    interactive: false,
    keyboard: false,
    zIndexOffset: -100, // below pins
  });
}

/**
 * Updates the label marker text and position.
 * If zone no longer has a name, returns false (caller should remove it).
 */
export function updateZoneLabelMarker(marker, zone, w, h) {
  if (!zone.name) return false;

  const span = marker.getElement()?.querySelector("span");
  if (span) span.textContent = zone.name;

  const center = computeCentroid(zone.vertices, w, h);
  marker.setLatLng(center);
  return true;
}

/**
 * Computes the visual centroid as the average of all vertex LatLngs.
 */
function computeCentroid(vertices, w, h) {
  if (!vertices || vertices.length === 0) return L.latLng(0, 0);
  const sum = vertices.reduce(
    (acc, v) => {
      const ll = toLatLng(v.x, v.y, w, h);
      return { lat: acc.lat + ll.lat, lng: acc.lng + ll.lng };
    },
    { lat: 0, lng: 0 },
  );
  return L.latLng(sum.lat / vertices.length, sum.lng / vertices.length);
}

/**
 * Converts zone vertices array to Leaflet LatLng array.
 */
function verticesToLatLngs(vertices, w, h) {
  return (vertices || []).map((v) => toLatLng(v.x, v.y, w, h));
}

/**
 * Builds Leaflet style options for a zone.
 */
function buildZoneStyle(zone) {
  return {
    color: zone.border_color || DEFAULT_BORDER_COLOR,
    weight: zone.border_width || 2,
    dashArray: DASH_PATTERNS[zone.border_style] || null,
    fillColor: zone.fill_color || DEFAULT_FILL_COLOR,
    fillOpacity: zone.opacity != null ? zone.opacity : 0.3,
    interactive: true,
  };
}
