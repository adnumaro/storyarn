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
}

/**
 * Updates a connection line's endpoints from pin markers.
 */
export function updateConnectionEndpoints(line, pinMarkers) {
  rebuildLatLngs(line, pinMarkers);
  // Forward decorator auto-updates (references the polyline).
  // Reverse decorator uses static coords — rebuild it.
  if (line._arrows?.reverse) {
    const map = line._map;
    line._arrows.reverse.remove();
    const reversed = [...line.getLatLngs()].reverse();
    line._arrows.reverse = makeArrowDecorator(reversed, line.connData);
    if (map) line._arrows.reverse.addTo(map);
  }
}

/**
 * Adds or removes selected styling on a connection line.
 */
export function setConnectionSelected(line, selected) {
  if (selected) {
    line.setStyle({ weight: SELECTED_WEIGHT, opacity: 1 });
  } else {
    const conn = line.connData;
    line.setStyle({
      weight: DEFAULT_WEIGHT,
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
  line.remove();
}

/**
 * Adds a line's arrow decorators to a layer/map.
 * Called by the handler after line.addTo().
 */
export function addArrowsToLayer(line, layer) {
  if (!line._arrows) return;
  if (line._arrows.forward) line._arrows.forward.addTo(layer);
  if (line._arrows.reverse) line._arrows.reverse.addTo(layer);
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
  // Re-add to map if the line is already on one
  if (line._map) {
    addArrowsToLayer(line, line._map);
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
// Style + geometry helpers
// =============================================================================

function buildConnectionStyle(conn) {
  return {
    color: conn.color || DEFAULT_COLOR,
    weight: DEFAULT_WEIGHT,
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
