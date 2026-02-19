/**
 * Connection rendering utilities for the map canvas.
 *
 * Creates Leaflet polylines between pins, styled with line colors and dash patterns.
 * Uses leaflet-polylinedecorator for arrowhead indicators:
 * - Unidirectional: single arrow pointing toward destination
 * - Bidirectional: arrows at both ends pointing outward
 */

import L from "leaflet";
import "leaflet-polylinedecorator/src/L.Symbol.js";
import "leaflet-polylinedecorator/src/L.PolylineDecorator.js";
import { toLatLng } from "./coordinate_utils.js";

const DEFAULT_COLOR = "#6b7280";
const SELECTED_WEIGHT = 4;
const DEFAULT_WEIGHT = 2;
const ARROW_SIZE = 14;

// line_style → Leaflet dashArray mapping
const DASH_PATTERNS = {
  solid: null,
  dashed: "10, 6",
  dotted: "3, 6",
};

/**
 * Creates a Leaflet polyline for a connection.
 * @returns {L.Polyline|null}
 */
export function createConnectionLine(conn, pinMarkers, w, h) {
  const fromMarker = pinMarkers.get(conn.from_pin_id);
  const toMarker = pinMarkers.get(conn.to_pin_id);

  if (!fromMarker || !toMarker) return null;

  const latLngs = buildLatLngs(fromMarker, toMarker, conn.waypoints, w, h);
  const line = L.polyline(latLngs, buildConnectionStyle(conn));

  line.connData = conn;
  line._canvasW = w;
  line._canvasH = h;
  line._pinMarkers = pinMarkers;

  // Arrow decorators (added to map by handler after line.addTo)
  line._arrows = buildArrows(line, conn);

  // Path label (deferred — added to map by handler via addLabelToLayer)
  line._labelData = { text: conn.label, color: conn.color, show: conn.show_label !== false };

  return line;
}

/**
 * Updates a connection line's style and waypoints.
 */
export function updateConnectionLine(line, conn) {
  const oldWaypoints = line.connData.waypoints || [];
  line.connData = conn;
  line.setStyle(buildConnectionStyle(conn));

  const newWaypoints = conn.waypoints || [];
  if (JSON.stringify(oldWaypoints) !== JSON.stringify(newWaypoints)) {
    rebuildLatLngs(line);
  }

  // Rebuild arrows (direction or color may have changed)
  replaceArrows(line, conn);

  // Update path label
  line._labelData = { text: conn.label, color: conn.color, show: conn.show_label !== false };
  applyLabel(line);
}

/**
 * Updates a connection line's endpoints from pin markers.
 */
export function updateConnectionEndpoints(line, pinMarkers) {
  rebuildLatLngs(line, pinMarkers);
  // Rebuild all arrows — the forward decorator does not reliably auto-update
  // when setLatLngs() is called during pin drag.
  replaceArrows(line, line.connData);
  // Reposition label at new midpoint
  applyLabel(line);
}

/**
 * Adds or removes selected styling on a connection line.
 */
export function setConnectionSelected(line, selected) {
  if (selected) {
    const baseWeight = line.connData?.line_width || DEFAULT_WEIGHT;
    line.setStyle({ weight: Math.max(baseWeight, SELECTED_WEIGHT), opacity: 1 });
  } else {
    const conn = line.connData;
    line.setStyle({
      weight: conn.line_width || DEFAULT_WEIGHT,
      opacity: 0.8,
      dashArray: DASH_PATTERNS[conn.line_style] || null,
    });
  }
}

/**
 * Removes a connection line and all its decorators from the map.
 */
export function removeConnectionLine(line) {
  removeArrows(line);
  removeLabel(line);
  line.remove();
}

/**
 * Adds a line's arrow decorators and label to a layer/map.
 * Called by the handler after line.addTo().
 */
export function addArrowsToLayer(line, layer) {
  if (!line._arrows) return;
  if (line._arrows.forward) line._arrows.forward.addTo(layer);
  if (line._arrows.reverse) line._arrows.reverse.addTo(layer);
  // Now that the line is on a map, create the label marker
  applyLabel(line);
}

// =============================================================================
// Arrow management
// =============================================================================

function buildArrows(line, conn) {
  // Arrows point INTO pins (headAngle 300 reverses the arrowhead direction).
  // Forward arrow (→ into destination): references the live polyline so it
  // auto-updates when the line moves (e.g. pin drag).
  // Reverse arrow (← into source): uses a static reversed snapshot; rebuilt
  // manually in updateConnectionEndpoints when pins move.
  const reversed = [...line.getLatLngs()].reverse();
  const arrows = {
    forward: makeArrowDecorator(line, conn),
    reverse: null,
  };

  if (conn.bidirectional) {
    arrows.reverse = makeArrowDecorator(reversed, conn);
  }

  return arrows;
}

function replaceArrows(line, conn) {
  removeArrows(line);
  line._arrows = buildArrows(line, conn);
  // Re-add to map if the line is already on one (arrows only — no label)
  if (line._map) {
    if (line._arrows.forward) line._arrows.forward.addTo(line._map);
    if (line._arrows.reverse) line._arrows.reverse.addTo(line._map);
  }
}

function removeArrows(line) {
  if (!line._arrows) return;
  if (line._arrows.forward) line._arrows.forward.remove();
  if (line._arrows.reverse) line._arrows.reverse.remove();
  line._arrows = null;
}

/**
 * Pixel distance from the pin where the arrow is drawn.
 * Uses pixel offset so it stays fixed regardless of zoom.
 */
const ARROW_OFFSET_PX = '10%';

function makeArrowDecorator(pathOrLatLngs, conn) {
  const color = conn.color || DEFAULT_COLOR;
  return L.polylineDecorator(pathOrLatLngs, {
    patterns: [
      {
        offset: ARROW_OFFSET_PX,
        repeat: 0,
        symbol: L.Symbol.arrowHead({
          pixelSize: ARROW_SIZE,
          headAngle: 300,
          polygon: true,
          pathOptions: {
            color,
            fillColor: color,
            weight: 0,
            opacity: 0.9,
            fillOpacity: 0.9,
            fill: true,
            stroke: false,
          },
        }),
      },
    ],
  });
}

// =============================================================================
// Path label — cartographic style (custom DivIcon marker at midpoint)
// =============================================================================

/**
 * Creates or updates the label marker at the path midpoint.
 *
 * Cartographic rules:
 * - Centered on the path's midpoint
 * - Offset above the line (never overlapping)
 * - Text angle follows the path segment but is never upside-down
 *   (normalized to −90°…+90° so it always reads naturally)
 */
function applyLabel(line) {
  removeLabel(line);

  const data = line._labelData;
  if (!data?.show) return;
  const text = data?.text?.trim();
  if (!text) return;

  const map = line._map;
  if (!map) return;

  const latLngs = line.getLatLngs();
  if (latLngs.length < 2) return;

  const { point: midLatLng, angle } = pathMidpointAndAngle(latLngs, map);

  const color = data.color || DEFAULT_COLOR;
  const escapedText = text.replace(/&/g, "&amp;").replace(/</g, "&lt;");

  const icon = L.divIcon({
    className: "",
    html:
      `<div style="` +
      `position:absolute;` +
      `transform:translate(-50%,-100%) rotate(${angle}deg);` +
      `transform-origin:center bottom;` +
      `white-space:nowrap;` +
      `font-size:13px;font-weight:600;` +
      `color:#fff;` +
      `background:rgba(0,0,0,0.45);` +
      `padding:1px 6px;border-radius:3px;` +
      `cursor:pointer;margin-bottom:4px;` +
      `">${escapedText}</div>`,
    iconSize: [0, 0],
    iconAnchor: [0, 0],
  });

  line._labelMarker = L.marker(midLatLng, {
    icon,
    interactive: true,
    zIndexOffset: -100,
  }).addTo(map);

  // Click on label → select the connection
  line._labelMarker.on("click", (e) => {
    L.DomEvent.stopPropagation(e);
    if (line._selectHandler) line._selectHandler();
  });
}

function removeLabel(line) {
  if (line._labelMarker) {
    line._labelMarker.remove();
    line._labelMarker = null;
  }
}

/**
 * Finds the geographic midpoint of a polyline and the readable angle (degrees)
 * of the segment at that point.
 */
function pathMidpointAndAngle(latLngs, map) {
  // Compute cumulative pixel distances per segment
  const pts = latLngs.map((ll) => map.latLngToContainerPoint(ll));
  const segLens = [];
  let total = 0;
  for (let i = 1; i < pts.length; i++) {
    const d = pts[i].distanceTo(pts[i - 1]);
    segLens.push(d);
    total += d;
  }

  // Walk to the halfway pixel distance
  let remaining = total / 2;
  let segIdx = 0;
  for (; segIdx < segLens.length - 1; segIdx++) {
    if (remaining <= segLens[segIdx]) break;
    remaining -= segLens[segIdx];
  }

  // Interpolation ratio within the segment
  const ratio = segLens[segIdx] > 0 ? remaining / segLens[segIdx] : 0;

  // Midpoint in geographic coords
  const lat =
    latLngs[segIdx].lat +
    (latLngs[segIdx + 1].lat - latLngs[segIdx].lat) * ratio;
  const lng =
    latLngs[segIdx].lng +
    (latLngs[segIdx + 1].lng - latLngs[segIdx].lng) * ratio;

  // Angle of the segment in screen space (y-down)
  const dx = pts[segIdx + 1].x - pts[segIdx].x;
  const dy = pts[segIdx + 1].y - pts[segIdx].y;
  let angle = (Math.atan2(dy, dx) * 180) / Math.PI;

  // Normalize to −90°…+90° so text is never upside-down
  if (angle > 90) angle -= 180;
  if (angle < -90) angle += 180;

  return { point: L.latLng(lat, lng), angle: Math.round(angle * 10) / 10 };
}

// =============================================================================
// Style + geometry helpers
// =============================================================================

function buildConnectionStyle(conn) {
  return {
    color: conn.color || DEFAULT_COLOR,
    weight: conn.line_width || DEFAULT_WEIGHT,
    dashArray: DASH_PATTERNS[conn.line_style] || null,
    opacity: 0.8,
    interactive: true,
  };
}

function buildLatLngs(fromMarker, toMarker, waypoints, w, h) {
  const points = [fromMarker.getLatLng()];

  if (waypoints && waypoints.length > 0) {
    for (const wp of waypoints) {
      points.push(toLatLng(wp.x, wp.y, w, h));
    }
  }

  points.push(toMarker.getLatLng());
  return points;
}

function rebuildLatLngs(line, pinMarkers) {
  const conn = line.connData;
  const markers = pinMarkers || line._pinMarkers;
  if (!markers) return;

  const fromMarker = markers.get(conn.from_pin_id);
  const toMarker = markers.get(conn.to_pin_id);
  if (!fromMarker || !toMarker) return;

  const latLngs = buildLatLngs(
    fromMarker,
    toMarker,
    conn.waypoints,
    line._canvasW,
    line._canvasH,
  );
  line.setLatLngs(latLngs);
}
