/**
 * Ruler / Distance Measurement tool for the map canvas.
 *
 * Click two points to measure the distance between them.
 * Distances shown in percentage units and optionally in map-defined units.
 * Measurements are ephemeral (not saved). Escape or tool switch clears them.
 */

import L from "leaflet";
import { toPercent } from "./coordinate_utils.js";

/**
 * Creates the ruler tool attached to the hook instance.
 * @param {Object} hook - The SceneCanvas hook instance
 */
export function createRuler(hook) {
  const map = hook.leafletMap;
  const w = hook.canvasWidth;
  const h = hook.canvasHeight;

  /** @type {{ line: L.Polyline, label: L.Tooltip, startMarker: L.CircleMarker, endMarker: L.CircleMarker }[]} */
  let measurements = [];
  let startPoint = null;
  let startMarker = null;
  let previewLine = null;

  // Bind map click for ruler mode
  map.on("click", onMapClick);

  // Bind keydown for Escape
  const handleKeyDown = (e) => {
    if (e.key === "Escape" && hook.currentTool === "ruler") {
      cancelDrawing();
      clear();
    }
  };
  document.addEventListener("keydown", handleKeyDown);

  // Preview line follows mouse during drawing
  map.on("mousemove", onMouseMove);

  function onMapClick(e) {
    if (hook.currentTool !== "ruler") return;

    // Prevent the deselect handler from firing
    L.DomEvent.stopPropagation(e);

    if (!startPoint) {
      // First click: set start
      startPoint = e.latlng;
      startMarker = L.circleMarker(startPoint, {
        radius: 5,
        color: "#f97316",
        fillColor: "#f97316",
        fillOpacity: 1,
        weight: 2,
        interactive: false,
      }).addTo(map);

      previewLine = L.polyline([startPoint, startPoint], {
        color: "#f97316",
        weight: 2,
        dashArray: "6 4",
        interactive: false,
      }).addTo(map);
    } else {
      // Second click: complete measurement
      const endPoint = e.latlng;
      finishMeasurement(startPoint, endPoint);

      // Clean up drawing state
      if (previewLine) {
        previewLine.remove();
        previewLine = null;
      }
      if (startMarker) {
        startMarker.remove();
        startMarker = null;
      }
      startPoint = null;
    }
  }

  function onMouseMove(e) {
    if (hook.currentTool !== "ruler" || !previewLine) return;
    previewLine.setLatLngs([startPoint, e.latlng]);
  }

  function finishMeasurement(from, to) {
    // Calculate distance in percentage space
    const pctFrom = toPercent(from, w, h);
    const pctTo = toPercent(to, w, h);
    const dx = pctTo.x - pctFrom.x;
    const dy = pctTo.y - pctFrom.y;
    const pctDist = Math.sqrt(dx * dx + dy * dy);

    // Build label text
    let labelText = `${pctDist.toFixed(1)}%`;

    const scaleUnit = hook.sceneData.scale_unit;
    const scaleValue = hook.sceneData.scale_value;
    if (scaleUnit && scaleValue && scaleValue > 0) {
      // Map width is 100%, so 1% = scaleValue / 100
      const realDist = (pctDist / 100) * scaleValue;
      labelText = `${formatNumber(realDist)} ${scaleUnit}`;
    }

    // Draw the measurement line
    const line = L.polyline([from, to], {
      color: "#f97316",
      weight: 2,
      dashArray: "6 4",
      interactive: false,
    }).addTo(map);

    // Start & end markers
    const sMarker = L.circleMarker(from, {
      radius: 5,
      color: "#f97316",
      fillColor: "#f97316",
      fillOpacity: 1,
      weight: 2,
      interactive: false,
    }).addTo(map);

    const eMarker = L.circleMarker(to, {
      radius: 5,
      color: "#f97316",
      fillColor: "#f97316",
      fillOpacity: 1,
      weight: 2,
      interactive: false,
    }).addTo(map);

    // Label at midpoint
    const midLat = (from.lat + to.lat) / 2;
    const midLng = (from.lng + to.lng) / 2;
    const midpoint = L.latLng(midLat, midLng);

    const label = L.tooltip({
      permanent: true,
      direction: "center",
      className: "map-ruler-label",
      interactive: false,
    })
      .setLatLng(midpoint)
      .setContent(labelText)
      .addTo(map);

    measurements.push({ line, label, startMarker: sMarker, endMarker: eMarker });
  }

  /** Cancels in-progress drawing (first click placed but not second). */
  function cancelDrawing() {
    if (previewLine) {
      previewLine.remove();
      previewLine = null;
    }
    if (startMarker) {
      startMarker.remove();
      startMarker = null;
    }
    startPoint = null;
  }

  /** Clears all measurements from the map. */
  function clear() {
    cancelDrawing();
    for (const m of measurements) {
      m.line.remove();
      m.label.remove();
      m.startMarker.remove();
      m.endMarker.remove();
    }
    measurements = [];
  }

  /** Removes event listeners and clears everything. */
  function destroy() {
    clear();
    map.off("click", onMapClick);
    map.off("mousemove", onMouseMove);
    document.removeEventListener("keydown", handleKeyDown);
  }

  return { clear, destroy };
}

/** Formats a number with up to 1 decimal place. */
function formatNumber(n) {
  if (Number.isInteger(n) || Math.abs(n - Math.round(n)) < 0.05) {
    return Math.round(n).toString();
  }
  return n.toFixed(1);
}
