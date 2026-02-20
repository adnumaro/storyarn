/**
 * Vertex editor for zone polygons on the map canvas.
 *
 * When a zone is selected, this module shows draggable vertex handles
 * at each vertex of the polygon. Dragging handles reshapes the polygon
 * in real time. On release, the updated vertices are pushed to the server.
 *
 * Features:
 * - Drag vertex handles to reshape polygon
 * - Click edge midpoints to add new vertices
 * - Ctrl+click a vertex to remove it (min 3 enforced)
 */

import L from "leaflet";
import { toPercent } from "./coordinate_utils.js";

const VERTEX_STYLE = {
  radius: 6,
  color: "#3b82f6",
  fillColor: "#ffffff",
  fillOpacity: 1,
  weight: 2,
  interactive: true,
};

const MIDPOINT_STYLE = {
  radius: 4,
  color: "#94a3b8",
  fillColor: "#e2e8f0",
  fillOpacity: 0.8,
  weight: 1,
  interactive: true,
};

/**
 * Creates a vertex editor instance.
 * @param {Object} hook - The MapCanvas hook instance
 * @returns {{ show(polygon), hide(), isActive() }}
 */
export function createVertexEditor(hook) {
  let activePolygon = null;
  let vertexMarkers = [];
  let midpointMarkers = [];
  const vertexGroup = L.layerGroup().addTo(hook.leafletMap);

  /**
   * Shows vertex handles for the given polygon.
   */
  function show(polygon) {
    hide();
    activePolygon = polygon;
    rebuildHandles();
  }

  /**
   * Hides all vertex handles.
   */
  function hide() {
    vertexGroup.clearLayers();
    vertexMarkers = [];
    midpointMarkers = [];
    activePolygon = null;
  }

  /**
   * Returns whether the vertex editor is currently active.
   */
  function isActive() {
    return activePolygon !== null;
  }

  /**
   * Rebuilds all vertex and midpoint handles from the polygon's current latLngs.
   */
  function rebuildHandles() {
    vertexGroup.clearLayers();
    vertexMarkers = [];
    midpointMarkers = [];

    if (!activePolygon) return;

    const latLngs = activePolygon.getLatLngs()[0]; // Polygons have nested arrays
    if (!latLngs || latLngs.length < 3) return;

    // Create vertex handles
    for (let i = 0; i < latLngs.length; i++) {
      const marker = createVertexHandle(latLngs[i], i);
      vertexMarkers.push(marker);
      vertexGroup.addLayer(marker);
    }

    // Create midpoint handles between each pair of vertices
    for (let i = 0; i < latLngs.length; i++) {
      const next = (i + 1) % latLngs.length;
      const midLatLng = midpoint(latLngs[i], latLngs[next]);
      const marker = createMidpointHandle(midLatLng, i);
      midpointMarkers.push(marker);
      vertexGroup.addLayer(marker);
    }
  }

  /**
   * Creates a draggable vertex handle at the given latLng.
   */
  function createVertexHandle(latLng, index) {
    const marker = L.circleMarker(latLng, {
      ...VERTEX_STYLE,
      className: "map-vertex-handle",
    });

    marker.vertexIndex = index;

    // Make it draggable via manual drag handling
    enableDrag(marker, index);

    // Ctrl+click to remove vertex
    marker.on("click", (e) => {
      if (e.originalEvent.ctrlKey || e.originalEvent.metaKey) {
        L.DomEvent.stopPropagation(e);
        removeVertex(index);
      }
    });

    return marker;
  }

  /**
   * Creates a midpoint handle. Clicking it inserts a new vertex.
   */
  function createMidpointHandle(latLng, afterIndex) {
    const marker = L.circleMarker(latLng, {
      ...MIDPOINT_STYLE,
      className: "map-midpoint-handle",
    });

    marker.on("click", (e) => {
      L.DomEvent.stopPropagation(e);
      insertVertex(afterIndex, latLng);
    });

    return marker;
  }

  /**
   * Enables drag behavior on a vertex handle circle marker.
   * CircleMarkers don't natively support dragging, so we implement it manually.
   */
  function enableDrag(marker, index) {
    let isDragging = false;

    marker.on("mousedown", (e) => {
      L.DomEvent.stopPropagation(e);
      L.DomEvent.preventDefault(e);
      isDragging = true;
      hook.leafletMap.dragging.disable();

      const onMove = (moveEvent) => {
        if (!isDragging) return;
        const newLatLng = moveEvent.latlng;
        marker.setLatLng(newLatLng);

        // Update the polygon in real time
        const latLngs = activePolygon.getLatLngs()[0];
        latLngs[index] = newLatLng;
        activePolygon.setLatLngs(latLngs);
      };

      const onUp = () => {
        isDragging = false;
        hook.leafletMap.off("mousemove", onMove);
        hook.leafletMap.off("mouseup", onUp);
        hook.updateCursor();

        // Persist the change and rebuild midpoints
        persistVertices();
        rebuildHandles();
      };

      hook.leafletMap.on("mousemove", onMove);
      hook.leafletMap.on("mouseup", onUp);
    });
  }

  /**
   * Removes a vertex at the given index (min 3 enforced).
   */
  function removeVertex(index) {
    const latLngs = activePolygon.getLatLngs()[0];
    if (latLngs.length <= 3) return; // Can't go below 3

    latLngs.splice(index, 1);
    activePolygon.setLatLngs(latLngs);
    persistVertices();
    rebuildHandles();
  }

  /**
   * Inserts a new vertex after the given index.
   */
  function insertVertex(afterIndex, latLng) {
    const latLngs = activePolygon.getLatLngs()[0];
    latLngs.splice(afterIndex + 1, 0, latLng);
    activePolygon.setLatLngs(latLngs);
    persistVertices();
    rebuildHandles();
  }

  /**
   * Converts polygon latLngs to percentages and pushes to server.
   */
  function persistVertices() {
    if (!activePolygon) return;

    const latLngs = activePolygon.getLatLngs()[0];
    const vertices = latLngs.map((ll) => {
      const p = toPercent(ll, hook.canvasWidth, hook.canvasHeight);
      return {
        x: Math.round(p.x * 100) / 100,
        y: Math.round(p.y * 100) / 100,
      };
    });

    const zone = activePolygon.zoneData;
    hook.pushEvent("update_zone_vertices", {
      id: zone.id,
      vertices: vertices,
    });

    // Update local zone data
    zone.vertices = vertices;
  }

  /**
   * Computes the midpoint between two latLngs.
   */
  function midpoint(a, b) {
    return L.latLng((a.lat + b.lat) / 2, (a.lng + b.lng) / 2);
  }

  return {
    show,
    hide,
    isActive,
  };
}
