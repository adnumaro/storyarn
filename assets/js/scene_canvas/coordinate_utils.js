/**
 * Coordinate utilities for the map canvas.
 *
 * The map stores positions as percentages (0–100).
 * Leaflet uses L.CRS.Simple with y-axis inverted: [y, x] as LatLng.
 * Image bounds go from [0, 0] (top-left) to [-height, width] in Leaflet coords.
 */

import L from "leaflet";

/**
 * Converts percentage coordinates (0–100) to Leaflet LatLng.
 * @param {number} x - Percentage X (0–100)
 * @param {number} y - Percentage Y (0–100)
 * @param {number} w - Image width in pixels
 * @param {number} h - Image height in pixels
 * @returns {L.LatLng}
 */
export function toLatLng(x, y, w, h) {
  const lx = (x / 100) * w;
  const ly = -((y / 100) * h);
  return L.latLng(ly, lx);
}

/**
 * Converts Leaflet LatLng back to percentage coordinates (0–100).
 * @param {L.LatLng} latLng
 * @param {number} w - Image width in pixels
 * @param {number} h - Image height in pixels
 * @returns {{ x: number, y: number }}
 */
export function toPercent(latLng, w, h) {
  const x = (latLng.lng / w) * 100;
  const y = (-latLng.lat / h) * 100;
  return { x: clamp(x, 0, 100), y: clamp(y, 0, 100) };
}

/**
 * Returns Leaflet bounds for the image overlay.
 * Top-left = [0, 0], bottom-right = [-h, w] in CRS.Simple.
 * @param {number} w - Image width in pixels
 * @param {number} h - Image height in pixels
 * @returns {L.LatLngBounds}
 */
export function imageBounds(w, h) {
  return L.latLngBounds([
    [0, 0],
    [-h, w],
  ]);
}

function clamp(val, min, max) {
  return Math.min(max, Math.max(min, val));
}
