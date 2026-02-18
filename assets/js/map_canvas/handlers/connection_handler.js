/**
 * Connection handler factory for the map canvas.
 *
 * Manages connection rendering, creation (in Connect mode via click source pin →
 * click target pin), selection, and keeping lines in sync with pin positions.
 *
 * Drawing state machine: idle → source selected → preview line → target → pushEvent
 *
 * Visual feedback during drawing:
 * - Connector tool active: pins show "connectable" ring on hover
 * - Source pin selected: source pin highlighted, dashed preview line follows cursor
 * - Hover target pin: target pin highlighted with success color
 * - Click target: connection created, all feedback removed
 * - Escape / canvas click / same pin: cancel drawing
 */

import L from "leaflet";
import {
  createConnectionLine,
  updateConnectionLine,
  updateConnectionEndpoints,
  setConnectionSelected,
  removeConnectionLine,
  addArrowsToLayer,
} from "../connection_renderer.js";
import { toPercent, toLatLng } from "../coordinate_utils.js";
import { editPropertiesItem, deleteItem } from "../context_menu_builder.js";

/**
 * Creates the connection handler attached to the hook instance.
 * @param {Object} hook - The MapCanvas hook instance
 * @param {Object} i18n - Translated label strings
 * @returns {{ init(), destroy(), renderConnections(), selectConnection(id), deselectAll(), updateEndpointsForPin(pinId) }}
 */
export function createConnectionHandler(hook, i18n = {}) {
  // Map of connection ID → L.Polyline
  const lines = new Map();

  // Drawing state
  let sourcePin = null;
  let previewLine = null;
  let hoveredPinId = null;

  // Waypoint editing state
  let waypointHandles = []; // L.CircleMarker[] for the currently selected connection
  let selectedConnId = null;

  function init() {
    renderConnections();
    wireServerEvents();
    wireDrawingEvents();
  }

  function destroy() {
    document.removeEventListener("keydown", handleKeyDown);
    cancelDrawing();
    removeWaypointHandles();
    for (const line of lines.values()) {
      removeConnectionLine(line);
    }
    lines.clear();
  }

  /** Renders all initial connections from mapData. */
  function renderConnections() {
    const connections = hook.mapData.connections || [];
    for (const conn of connections) {
      addConnectionToMap(conn);
    }
  }

  /** Adds a single connection line to the Leaflet map. */
  function addConnectionToMap(conn) {
    const pinMarkers = hook.pinHandler.markers;
    const line = createConnectionLine(
      conn,
      pinMarkers,
      hook.canvasWidth,
      hook.canvasHeight,
    );

    if (!line) return;

    // Click → select (also used by label marker)
    line._selectHandler = () => {
      hook.pushEvent("select_element", { type: "connection", id: conn.id });
    };

    line.on("click", (e) => {
      L.DomEvent.stopPropagation(e);
      line._selectHandler();
    });

    // Right-click → context menu
    line.on("contextmenu", (e) => {
      L.DomEvent.stopPropagation(e);
      L.DomEvent.preventDefault(e);
      if (!hook.contextMenu || !hook.editMode) return;

      const containerPoint = hook.leafletMap.latLngToContainerPoint(e.latlng);
      hook.contextMenu.show(containerPoint.x, containerPoint.y, [
        editPropertiesItem("connection", conn.id, hook, i18n),
        { separator: true },
        deleteItem("connection", conn.id, hook, i18n),
      ]);
    });

    // Double-click → add waypoint at click position
    line.on("dblclick", (e) => {
      L.DomEvent.stopPropagation(e);
      if (!hook.editMode) return;

      const pos = toPercent(e.latlng, hook.canvasWidth, hook.canvasHeight);
      const currentWaypoints = [...(line.connData.waypoints || [])];

      // Find the best insertion index (closest segment)
      const insertIdx = findInsertionIndex(line, e.latlng);
      currentWaypoints.splice(insertIdx, 0, { x: pos.x, y: pos.y });

      hook.pushEvent("update_connection_waypoints", {
        id: String(conn.id),
        waypoints: currentWaypoints,
      });
    });

    line.addTo(hook.connectionLayer);
    addArrowsToLayer(line, hook.connectionLayer);
    lines.set(conn.id, line);
  }

  /** Wires drawing events for Connect mode. */
  function wireDrawingEvents() {
    document.addEventListener("keydown", handleKeyDown);

    // Cancel drawing on canvas click (not on a pin)
    hook.leafletMap.on("click", handleCanvasClick);
  }

  function handleKeyDown(e) {
    if (e.key === "Escape" && sourcePin) {
      cancelDrawing();
    }
  }

  /** Cancels drawing when clicking empty canvas while in connector mode. */
  function handleCanvasClick() {
    if (sourcePin && hook.currentTool === "connector") {
      cancelDrawing();
    }
  }

  /**
   * Called by pin_handler when a pin is clicked in connect mode.
   * Implements the source → target state machine.
   */
  function handlePinClickInConnectMode(pinId) {
    if (!sourcePin) {
      // First click: set source
      sourcePin = pinId;
      setPinVisualState(pinId, "source");

      // Start preview line from source pin
      const fromMarker = hook.pinHandler.markers.get(pinId);
      if (fromMarker) {
        const fromLatLng = fromMarker.getLatLng();
        previewLine = L.polyline([fromLatLng, fromLatLng], {
          color: "#3b82f6",
          weight: 2,
          dashArray: "6, 4",
          opacity: 0.6,
          interactive: false,
        }).addTo(hook.leafletMap);

        // Update preview line on mousemove
        hook.leafletMap.on("mousemove", updatePreviewLine);
      }
    } else if (pinId === sourcePin) {
      // Click same pin → cancel
      cancelDrawing();
    } else {
      // Second click on different pin: create connection
      const fromPinId = sourcePin;
      const toPinId = pinId;

      cancelDrawing();

      hook.pushEvent("create_connection", {
        from_pin_id: fromPinId,
        to_pin_id: toPinId,
      });
    }
  }

  /** Updates the preview line endpoint to follow the cursor. */
  function updatePreviewLine(e) {
    if (previewLine) {
      const latLngs = previewLine.getLatLngs();
      previewLine.setLatLngs([latLngs[0], e.latlng]);
    }
  }

  /** Cancels the current drawing session and clears all visual feedback. */
  function cancelDrawing() {
    if (sourcePin) {
      clearPinVisualState(sourcePin);
    }
    if (hoveredPinId) {
      clearPinVisualState(hoveredPinId);
      hoveredPinId = null;
    }
    sourcePin = null;

    if (previewLine) {
      previewLine.remove();
      previewLine = null;
    }

    hook.leafletMap.off("mousemove", updatePreviewLine);
  }

  // ---------------------------------------------------------------------------
  // Pin visual feedback for connector mode
  // ---------------------------------------------------------------------------

  /**
   * Called by pin_handler on mouseover when connector tool is active.
   * Shows "connectable" hint, or "target" hint if source is already selected.
   */
  function handlePinMouseOver(pinId) {
    if (hook.currentTool !== "connector") return;

    if (sourcePin && pinId !== sourcePin) {
      // Source already selected, this is a candidate target
      setPinVisualState(pinId, "target");
    } else if (!sourcePin) {
      // No source yet, show connectable hint
      setPinVisualState(pinId, "connectable");
    }
    hoveredPinId = pinId;
  }

  /**
   * Called by pin_handler on mouseout when connector tool is active.
   * Removes hover feedback (but keeps source highlight).
   */
  function handlePinMouseOut(pinId) {
    if (pinId === sourcePin) return; // Don't remove source highlight
    clearPinVisualState(pinId);
    if (hoveredPinId === pinId) hoveredPinId = null;
  }

  /**
   * Adds a CSS class to a pin marker element for visual feedback.
   * @param {number|string} pinId
   * @param {"connectable"|"source"|"target"} state
   */
  function setPinVisualState(pinId, state) {
    const marker = hook.pinHandler.markers.get(pinId);
    if (!marker) return;
    const el = marker.getElement();
    if (!el) return;
    // Remove any previous connection state classes
    el.classList.remove("map-pin-connectable", "map-pin-source", "map-pin-target");
    el.classList.add(`map-pin-${state}`);
  }

  /** Removes all connection visual state classes from a pin marker. */
  function clearPinVisualState(pinId) {
    const marker = hook.pinHandler.markers.get(pinId);
    if (!marker) return;
    const el = marker.getElement();
    if (!el) return;
    el.classList.remove("map-pin-connectable", "map-pin-source", "map-pin-target");
  }

  // ---------------------------------------------------------------------------
  // Waypoint handle editing
  // ---------------------------------------------------------------------------

  /**
   * Finds the best segment index to insert a new waypoint.
   * Returns the index in the waypoints array (0 = before first waypoint).
   */
  function findInsertionIndex(line, latlng) {
    const latLngs = line.getLatLngs();
    if (latLngs.length < 2) return 0;

    let bestIdx = 0;
    let bestDist = Infinity;

    for (let i = 0; i < latLngs.length - 1; i++) {
      const dist = distToSegment(latlng, latLngs[i], latLngs[i + 1]);
      if (dist < bestDist) {
        bestDist = dist;
        // The first segment (pin → first wp) maps to index 0 in waypoints
        // Index i in latLngs corresponds to waypoint index (i - 1 + 1) = i
        // because latLngs[0] = from_pin, latLngs[1..n-1] = waypoints, latLngs[n] = to_pin
        bestIdx = i; // Insert after segment start, which is waypoint index i
      }
    }

    return bestIdx;
  }

  /** Distance from a point to a line segment. */
  function distToSegment(p, a, b) {
    const dx = b.lng - a.lng;
    const dy = b.lat - a.lat;
    const lenSq = dx * dx + dy * dy;

    if (lenSq === 0) return p.distanceTo(a);

    let t = ((p.lng - a.lng) * dx + (p.lat - a.lat) * dy) / lenSq;
    t = Math.max(0, Math.min(1, t));

    const proj = L.latLng(a.lat + t * dy, a.lng + t * dx);
    return p.distanceTo(proj);
  }

  /** Shows draggable handles for all waypoints of a selected connection. */
  function showWaypointHandles(connId) {
    removeWaypointHandles();
    selectedConnId = connId;

    const line = lines.get(connId);
    if (!line || !hook.editMode) return;

    const waypoints = line.connData.waypoints || [];
    if (waypoints.length === 0) return;

    for (let i = 0; i < waypoints.length; i++) {
      const wp = waypoints[i];
      const latlng = toLatLng(wp.x, wp.y, hook.canvasWidth, hook.canvasHeight);

      const handle = L.circleMarker(latlng, {
        radius: 6,
        color: "#3b82f6",
        fillColor: "#ffffff",
        fillOpacity: 1,
        weight: 2,
        interactive: true,
        bubblingMouseEvents: false,
      });

      handle._wpIndex = i;
      handle.addTo(hook.leafletMap);

      // Drag waypoint
      enableHandleDrag(handle, connId);

      // Right-click → remove waypoint
      handle.on("contextmenu", (e) => {
        L.DomEvent.stopPropagation(e);
        L.DomEvent.preventDefault(e);
        removeWaypoint(connId, handle._wpIndex);
      });

      waypointHandles.push(handle);
    }
  }

  /** Enables drag behavior on a waypoint handle. */
  function enableHandleDrag(handle, connId) {
    let dragging = false;

    handle.on("mousedown", (e) => {
      L.DomEvent.stopPropagation(e);
      dragging = true;
      hook.leafletMap.dragging.disable();

      const onMove = (moveEvent) => {
        handle.setLatLng(moveEvent.latlng);
        // Update line in real time
        updateLineFromHandles(connId);
      };

      const onUp = () => {
        dragging = false;
        hook.leafletMap.off("mousemove", onMove);
        hook.leafletMap.off("mouseup", onUp);
        hook.updateCursor();

        // Persist the new waypoint positions
        persistWaypoints(connId);
      };

      hook.leafletMap.on("mousemove", onMove);
      hook.leafletMap.on("mouseup", onUp);
    });
  }

  /** Updates the connection line to match current waypoint handle positions. */
  function updateLineFromHandles(connId) {
    const line = lines.get(connId);
    if (!line) return;

    const fromMarker = hook.pinHandler.markers.get(line.connData.from_pin_id);
    const toMarker = hook.pinHandler.markers.get(line.connData.to_pin_id);
    if (!fromMarker || !toMarker) return;

    const latLngs = [fromMarker.getLatLng()];
    for (const h of waypointHandles) {
      latLngs.push(h.getLatLng());
    }
    latLngs.push(toMarker.getLatLng());
    line.setLatLngs(latLngs);
  }

  /** Converts current handle positions to waypoints and pushes to server. */
  function persistWaypoints(connId) {
    const waypoints = waypointHandles.map((h) => {
      const pos = toPercent(h.getLatLng(), hook.canvasWidth, hook.canvasHeight);
      return { x: pos.x, y: pos.y };
    });

    hook.pushEvent("update_connection_waypoints", {
      id: String(connId),
      waypoints,
    });
  }

  /** Removes a waypoint at the given index and persists. */
  function removeWaypoint(connId, wpIndex) {
    const line = lines.get(connId);
    if (!line) return;

    const currentWaypoints = [...(line.connData.waypoints || [])];
    currentWaypoints.splice(wpIndex, 1);

    hook.pushEvent("update_connection_waypoints", {
      id: String(connId),
      waypoints: currentWaypoints,
    });
  }

  /** Removes all waypoint handles from the map. */
  function removeWaypointHandles() {
    for (const h of waypointHandles) {
      h.remove();
    }
    waypointHandles = [];
    selectedConnId = null;
  }

  /**
   * Called when the tool changes away from connector.
   * Clears all visual states from all pins.
   */
  function clearAllPinStates() {
    for (const marker of hook.pinHandler.markers.values()) {
      const el = marker.getElement();
      if (el) {
        el.classList.remove("map-pin-connectable", "map-pin-source", "map-pin-target");
      }
    }
  }

  /** Wires handleEvent listeners from the server. */
  function wireServerEvents() {
    hook.handleEvent("connection_created", (conn) => {
      addConnectionToMap(conn);
    });

    hook.handleEvent("connection_updated", (conn) => {
      const line = lines.get(conn.id);
      if (line) {
        updateConnectionLine(line, conn);
        // Refresh waypoint handles if this connection is selected
        if (selectedConnId === conn.id) {
          showWaypointHandles(conn.id);
        }
      }
    });

    hook.handleEvent("connection_deleted", ({ id }) => {
      const line = lines.get(id);
      if (line) {
        removeConnectionLine(line);
        lines.delete(id);
      }
    });
  }

  /**
   * Updates the endpoints of all connections linked to a given pin.
   * Called by pin_handler after a pin drag.
   */
  function updateEndpointsForPin(pinId) {
    const pinMarkers = hook.pinHandler.markers;
    for (const line of lines.values()) {
      const conn = line.connData;
      if (conn.from_pin_id === pinId || conn.to_pin_id === pinId) {
        updateConnectionEndpoints(line, pinMarkers);
      }
    }
  }

  /** Highlights the selected connection, un-highlights all others. */
  function selectConnection(connId) {
    for (const [id, line] of lines) {
      setConnectionSelected(line, id === connId);
    }
    // Show waypoint handles for the selected connection
    showWaypointHandles(connId);
  }

  /** Clears selection highlight from all connections. */
  function deselectAll() {
    for (const line of lines.values()) {
      setConnectionSelected(line, false);
    }
    removeWaypointHandles();
  }

  // ---------------------------------------------------------------------------
  // Search highlight helpers
  // ---------------------------------------------------------------------------

  /** Sets a single connection's dimmed state. */
  function setDimmed(connId, dimmed) {
    const line = lines.get(connId);
    if (!line) return;
    line.setStyle({ opacity: dimmed ? 0.15 : 0.8 });
  }

  /** Dims or un-dims all connections. */
  function setAllDimmed(dimmed) {
    for (const line of lines.values()) {
      line.setStyle({ opacity: dimmed ? 0.15 : 0.8 });
    }
  }

  /** Clears all dimming (restores default opacity). */
  function clearDimming() {
    for (const line of lines.values()) {
      line.setStyle({ opacity: 0.8 });
    }
  }

  /** Rebuilds all connection line geometries (after canvas resize / pin reposition). */
  function repositionAll() {
    const pinMarkers = hook.pinHandler.markers;
    for (const line of lines.values()) {
      updateConnectionEndpoints(line, pinMarkers);
    }
  }

  return {
    init,
    destroy,
    renderConnections,
    repositionAll,
    selectConnection,
    deselectAll,
    updateEndpointsForPin,
    handlePinClickInConnectMode,
    handlePinMouseOver,
    handlePinMouseOut,
    cancelDrawing,
    clearAllPinStates,
    setDimmed,
    setAllDimmed,
    clearDimming,
    lines,
  };
}
