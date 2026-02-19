/**
 * Zone handler factory for the map canvas.
 *
 * Manages zone rendering, creation (in Zone mode via click-to-place vertices),
 * and selection.
 *
 * Drawing state machine: idle → collecting → close (click near first vertex) → pushEvent
 */

import L from "leaflet";
import {
  createZonePolygon,
  createZoneLabelMarker,
  setZoneSelected,
  updateZonePolygon,
  updateZoneLabelMarker,
  updateZoneVertices,
} from "../zone_renderer.js";
import { toLatLng, toPercent } from "../coordinate_utils.js";
import { createVertexEditor } from "../vertex_editor.js";
import { getShapePreset } from "../shape_presets.js";
import {
  editPropertiesItem,
  bringToFrontItem,
  sendToBackItem,
  lockToggleItem,
  deleteItem,
} from "../context_menu_builder.js";

/**
 * Creates the zone handler attached to the hook instance.
 * @param {Object} hook - The MapCanvas hook instance
 * @param {Object} i18n - Translated label strings
 * @returns {{ init(), destroy(), renderZones(), selectZone(id), deselectAll() }}
 */
// Distance in pixels to detect clicking near the first vertex
const CLOSE_THRESHOLD_PX = 15;

export function createZoneHandler(hook, i18n = {}) {
  // Map of zone ID → L.Polygon
  const polygons = new Map();
  // Map of zone ID → L.Marker (centroid label)
  const labelMarkers = new Map();

  // Vertex editor for selected zones
  const vertexEditor = createVertexEditor(hook);

  // Drawing state (freeform)
  let drawingVertices = [];
  let vertexMarkers = [];
  let previewPolygon = null;

  // Ghost preview state (shape presets)
  let ghostPolygon = null;

  // Drag state (zone move)
  let dragging = false;
  let dragPolygon = null;
  let dragStartLatLng = null;
  let dragOriginalLatLngs = null;

  function init() {
    renderZones();
    setupDrawingHandlers();
    wireServerEvents();
  }

  function destroy() {
    document.removeEventListener("keydown", handleKeyDown);
    hook.leafletMap.off("mousemove", onDragMove);
    hook.leafletMap.off("mouseup", onDragEnd);
    vertexEditor.hide();
    cancelDrawing();
    removeGhost();
    cancelDrag();
    polygons.clear();
    labelMarkers.clear();
  }

  /** Renders all initial zones from mapData, sorted by position for z-ordering. */
  function renderZones() {
    const zones = (hook.mapData.zones || []).slice().sort((a, b) => (a.position || 0) - (b.position || 0));
    for (const zone of zones) {
      addZoneToMap(zone);
    }
  }

  /** Re-applies z-order to all zone polygons by calling bringToFront in ascending position order. */
  function reapplyZoneOrder() {
    const sorted = [...polygons.entries()].sort(
      (a, b) => (a[1].zoneData.position || 0) - (b[1].zoneData.position || 0),
    );
    for (const [, polygon] of sorted) {
      polygon.bringToFront();
    }
  }

  /** Adds a single zone polygon to the Leaflet map. */
  function addZoneToMap(zone) {
    const polygon = createZonePolygon(zone, hook.canvasWidth, hook.canvasHeight);
    polygon.zoneData = zone;

    // Click → select
    polygon.on("click", (e) => {
      L.DomEvent.stopPropagation(e);
      hook.pushEvent("select_element", { type: "zone", id: polygon.zoneData.id });
    });

    // Double-click → navigate to child map, or create one if none exists
    polygon.on("dblclick", (e) => {
      L.DomEvent.stopPropagation(e);
      L.DomEvent.preventDefault(e);

      const isZoneTool = hook.isZoneTool && hook.isZoneTool(hook.currentTool);
      if (isZoneTool) return;

      if (polygon.zoneData.target_type === "map" && polygon.zoneData.target_id) {
        // Navigate to existing child map
        hook.pushEvent("navigate_to_target", {
          type: "map",
          id: polygon.zoneData.target_id,
        });
      } else if (hook.editMode) {
        // No child map yet — create one (server validates zone has a name)
        hook.pushEvent("create_child_map_from_zone", {
          zone_id: String(polygon.zoneData.id),
        });
      }
    });

    // Hover effects: slight opacity increase (reads from zoneData to avoid stale closure)
    polygon.on("mouseover", () => {
      if (!polygon._selected) {
        const currentOpacity = polygon.zoneData?.opacity ?? 0.3;
        polygon.setStyle({ fillOpacity: Math.min(currentOpacity + 0.15, 1) });
      }
    });

    polygon.on("mouseout", () => {
      if (!polygon._selected) {
        const currentOpacity = polygon.zoneData?.opacity ?? 0.3;
        polygon.setStyle({ fillOpacity: currentOpacity });
      }
      // Reset cursor when leaving a selected zone (if not dragging)
      if (!dragging) {
        const el = polygon.getElement();
        if (el) el.style.cursor = "";
      }
    });

    // Drag: show grab cursor on selected zones in select mode
    polygon.on("mouseover", () => {
      if (polygon.zoneData.locked) return;
      if (polygon._selected && hook.currentTool === "select" && hook.editMode) {
        const el = polygon.getElement();
        if (el) el.style.cursor = "grab";
      }
    });

    // Drag: start on mousedown of a selected zone in select mode
    polygon.on("mousedown", (e) => {
      if (!polygon._selected) return;
      if (hook.currentTool !== "select") return;
      if (!hook.editMode) return;
      if (polygon.zoneData.locked) return;

      L.DomEvent.stopPropagation(e);
      L.DomEvent.preventDefault(e);

      dragging = true;
      hook.floatingToolbar?.setDragging(true);
      dragPolygon = polygon;
      dragStartLatLng = e.latlng;
      dragOriginalLatLngs = polygon.getLatLngs()[0].map((ll) => L.latLng(ll.lat, ll.lng));

      // Disable map dragging during zone drag
      hook.leafletMap.dragging.disable();

      const el = polygon.getElement();
      if (el) el.style.cursor = "grabbing";

      // Hide vertex editor during drag for clean visuals
      vertexEditor.hide();

      hook.leafletMap.on("mousemove", onDragMove);
      hook.leafletMap.on("mouseup", onDragEnd);
    });

    // Right-click → context menu
    polygon.on("contextmenu", (e) => {
      L.DomEvent.stopPropagation(e);
      L.DomEvent.preventDefault(e);
      if (!hook.contextMenu || !hook.editMode) return;

      const containerPoint = hook.leafletMap.latLngToContainerPoint(e.latlng);
      const zoneId = polygon.zoneData.id;
      const data = polygon.zoneData;

      const items = [editPropertiesItem("zone", zoneId, hook, i18n)];

      // Only show edit/duplicate when not locked
      if (!data.locked) {
        items.push({
          label: i18n.duplicate || "Duplicate",
          action: () => hook.pushEvent("duplicate_zone", { id: String(zoneId) }),
        });
        items.push({
          label: i18n.create_child_map || "Create child map",
          disabled: !data.name || data.name.trim() === "",
          tooltip: !data.name
            ? (i18n.name_zone_first || "Name the zone first")
            : null,
          action: () =>
            hook.pushEvent("create_child_map_from_zone", {
              zone_id: String(zoneId),
            }),
        });
      }

      items.push({ separator: true });
      items.push(bringToFrontItem("zone", zoneId, getMaxPosition(), hook, i18n));
      items.push(sendToBackItem("zone", zoneId, getMinPosition(), hook, i18n));
      items.push({ separator: true });
      items.push(lockToggleItem("zone", zoneId, data.locked, hook, i18n));

      if (!data.locked) {
        items.push({ separator: true });
        items.push(deleteItem("zone", zoneId, hook, i18n));
      }

      hook.contextMenu.show(containerPoint.x, containerPoint.y, items);
    });

    // Tooltip
    if (zone.tooltip) {
      polygon.bindTooltip(zone.tooltip, { sticky: true, className: "map-zone-tooltip" });
    }

    // Link cursor for zones with a target
    if (zone.target_type === "map" && zone.target_id) {
      polygon.getElement && polygon.on("add", () => {
        const el = polygon.getElement();
        if (el) el.style.cursor = "pointer";
      });
    }

    polygon.addTo(hook.zoneLayer);
    polygons.set(zone.id, polygon);

    // Zone label at centroid
    const label = createZoneLabelMarker(zone, hook.canvasWidth, hook.canvasHeight);
    if (label) {
      label.addTo(hook.zoneLayer);
      labelMarkers.set(zone.id, label);
    }
  }

  /** Computes shape vertices for a preset tool at a given position, applying aspect ratio for circles. */
  function computeShapeVertices(tool, pos) {
    const presetFn = getShapePreset(tool);
    if (!presetFn) return null;
    if (tool === "circle") {
      return presetFn(pos.x, pos.y, undefined, hook.canvasWidth / hook.canvasHeight);
    }
    return presetFn(pos.x, pos.y);
  }

  /** Sets up click/dblclick/mousemove handlers for zone creation. */
  function setupDrawingHandlers() {
    hook.leafletMap.on("click", (e) => {
      const isZoneTool = hook.isZoneTool && hook.isZoneTool(hook.currentTool);
      if (!isZoneTool) return;

      // Prevent if clicking on existing interactive elements
      if (e.originalEvent._stopped) return;

      const tool = hook.currentTool;
      const vertices = computeShapeVertices(tool, toPercent(e.latlng, hook.canvasWidth, hook.canvasHeight));

      if (vertices) {
        // Shape preset: single click creates zone immediately
        removeGhost();
        hook.pushEvent("create_zone", { name: "", vertices });
      } else {
        // Freeform: collect vertices or close polygon
        const latLng = e.latlng;

        // Auto-close: if 3+ vertices and click is near first vertex, finish
        if (drawingVertices.length >= 3 && isNearFirstVertex(e)) {
          finishDrawing();
          return;
        }

        drawingVertices.push(latLng);

        const isFirst = drawingVertices.length === 1;
        const marker = L.circleMarker(latLng, {
          radius: isFirst ? 7 : 5,
          color: "#3b82f6",
          fillColor: isFirst ? "#60a5fa" : "#3b82f6",
          fillOpacity: 1,
          weight: 2,
          interactive: false,
          className: isFirst ? "map-zone-close-target" : "",
        }).addTo(hook.leafletMap);
        vertexMarkers.push(marker);

        // After 3+ vertices, make first vertex pulse to indicate close target
        if (drawingVertices.length === 3 && vertexMarkers[0]) {
          const el = vertexMarkers[0].getElement();
          if (el) el.classList.add("map-zone-close-target");
        }

        updatePreview();
      }
    });

    // Ghost preview for shape presets
    hook.leafletMap.on("mousemove", (e) => {
      const tool = hook.currentTool;
      const vertices = computeShapeVertices(tool, toPercent(e.latlng, hook.canvasWidth, hook.canvasHeight));
      if (!vertices) {
        removeGhost();
        return;
      }

      const latLngs = vertices.map((v) =>
        toLatLng(v.x, v.y, hook.canvasWidth, hook.canvasHeight),
      );

      if (ghostPolygon) {
        ghostPolygon.setLatLngs(latLngs);
      } else {
        ghostPolygon = L.polygon(latLngs, {
          color: "#3b82f6",
          weight: 2,
          dashArray: "6, 4",
          fillColor: "#3b82f6",
          fillOpacity: 0.1,
          interactive: false,
        }).addTo(hook.leafletMap);
      }
    });

    // Escape cancels drawing
    document.addEventListener("keydown", handleKeyDown);
  }

  function handleKeyDown(e) {
    if (e.key === "Escape" && drawingVertices.length > 0) {
      cancelDrawing();
    }
  }

  /** Checks if a click event is within CLOSE_THRESHOLD_PX of the first vertex. */
  function isNearFirstVertex(e) {
    if (drawingVertices.length === 0) return false;
    const firstLatLng = drawingVertices[0];
    const firstPoint = hook.leafletMap.latLngToContainerPoint(firstLatLng);
    const clickPoint = hook.leafletMap.latLngToContainerPoint(e.latlng);
    const dist = firstPoint.distanceTo(clickPoint);
    return dist <= CLOSE_THRESHOLD_PX;
  }

  /** Updates the dashed preview polygon during drawing. */
  function updatePreview() {
    if (previewPolygon) {
      previewPolygon.setLatLngs(drawingVertices);
    } else if (drawingVertices.length >= 2) {
      previewPolygon = L.polygon(drawingVertices, {
        color: "#3b82f6",
        weight: 2,
        dashArray: "6, 4",
        fillColor: "#3b82f6",
        fillOpacity: 0.1,
        interactive: false,
      }).addTo(hook.leafletMap);
    }
  }

  /** Finishes drawing: converts vertices to percentages and pushes event. */
  function finishDrawing() {
    const vertices = drawingVertices.map((latLng) => {
      const p = toPercent(latLng, hook.canvasWidth, hook.canvasHeight);
      return { x: Math.round(p.x * 100) / 100, y: Math.round(p.y * 100) / 100 };
    });

    // Clean up drawing artifacts
    cleanupDrawingArtifacts();

    // Prompt for name
    // Using pushEvent to let the server handle naming
    hook.pushEvent("create_zone", {
      name: "",
      vertices: vertices,
    });
  }

  /** Cancels the current drawing session. */
  function cancelDrawing() {
    cleanupDrawingArtifacts();
    removeGhost();
  }

  /** Removes all freeform drawing artifacts (markers, preview polygon). */
  function cleanupDrawingArtifacts() {
    for (const m of vertexMarkers) {
      m.remove();
    }
    vertexMarkers = [];
    drawingVertices = [];

    if (previewPolygon) {
      previewPolygon.remove();
      previewPolygon = null;
    }
  }

  /** Removes the ghost preview polygon for shape presets. */
  function removeGhost() {
    if (ghostPolygon) {
      ghostPolygon.remove();
      ghostPolygon = null;
    }
  }

  /** Cancels an in-progress zone drag, restoring original position. */
  function cancelDrag() {
    if (!dragging) return;

    hook.leafletMap.off("mousemove", onDragMove);
    hook.leafletMap.off("mouseup", onDragEnd);
    hook.leafletMap.dragging.enable();

    // Restore original position
    if (dragPolygon && dragOriginalLatLngs) {
      dragPolygon.setLatLngs(dragOriginalLatLngs);
    }

    dragging = false;
    dragPolygon = null;
    dragStartLatLng = null;
    dragOriginalLatLngs = null;
  }

  // ---------------------------------------------------------------------------
  // Zone drag handlers
  // ---------------------------------------------------------------------------

  /** Updates polygon position during drag. */
  function onDragMove(e) {
    if (!dragging || !dragPolygon || !dragStartLatLng) return;

    const dLat = e.latlng.lat - dragStartLatLng.lat;
    const dLng = e.latlng.lng - dragStartLatLng.lng;

    const newLatLngs = dragOriginalLatLngs.map(
      (ll) => L.latLng(ll.lat + dLat, ll.lng + dLng),
    );

    dragPolygon.setLatLngs(newLatLngs);

    // Move the label marker to the new centroid
    const label = labelMarkers.get(dragPolygon.zoneData.id);
    if (label) {
      const sum = newLatLngs.reduce(
        (acc, ll) => ({ lat: acc.lat + ll.lat, lng: acc.lng + ll.lng }),
        { lat: 0, lng: 0 },
      );
      label.setLatLng(L.latLng(sum.lat / newLatLngs.length, sum.lng / newLatLngs.length));
    }
  }

  /** Finishes drag: clamps vertices, persists to server. */
  function onDragEnd() {
    if (!dragging || !dragPolygon) return;

    hook.leafletMap.off("mousemove", onDragMove);
    hook.leafletMap.off("mouseup", onDragEnd);
    hook.leafletMap.dragging.enable();

    // Convert current polygon latlngs to percentage vertices, clamped to 0-100
    const latLngs = dragPolygon.getLatLngs()[0];
    const vertices = latLngs.map((ll) => {
      const p = toPercent(ll, hook.canvasWidth, hook.canvasHeight);
      return { x: Math.round(p.x * 100) / 100, y: Math.round(p.y * 100) / 100 };
    });

    // Clamp: if any vertex is out of bounds, compute the delta needed to bring it back
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const v of vertices) {
      if (v.x < minX) minX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.x > maxX) maxX = v.x;
      if (v.y > maxY) maxY = v.y;
    }

    let adjustX = 0, adjustY = 0;
    if (minX < 0) adjustX = -minX;
    else if (maxX > 100) adjustX = 100 - maxX;
    if (minY < 0) adjustY = -minY;
    else if (maxY > 100) adjustY = 100 - maxY;

    const clampedVertices = vertices.map((v) => ({
      x: Math.round((v.x + adjustX) * 100) / 100,
      y: Math.round((v.y + adjustY) * 100) / 100,
    }));

    const zoneId = dragPolygon.zoneData.id;

    // Reset cursor
    const el = dragPolygon.getElement();
    if (el) el.style.cursor = "grab";

    // Clean up drag state
    dragging = false;
    hook.floatingToolbar?.setDragging(false);
    dragPolygon = null;
    dragStartLatLng = null;
    dragOriginalLatLngs = null;

    // Push to server
    hook.pushEvent("update_zone_vertices", {
      id: String(zoneId),
      vertices: clampedVertices,
    });

    // Re-show vertex editor after drag
    selectZone(zoneId);
  }

  /** Wires handleEvent listeners from the server. */
  function wireServerEvents() {
    hook.handleEvent("zone_created", (zone) => {
      addZoneToMap(zone);
      if (hook.layerHandler) hook.layerHandler.rebuildFog();
    });

    hook.handleEvent("zone_updated", (zone) => {
      const polygon = polygons.get(zone.id);
      if (polygon) {
        polygon.zoneData = zone;
        updateZonePolygon(polygon, zone);

        // Update tooltip
        polygon.unbindTooltip();
        if (zone.tooltip) {
          polygon.bindTooltip(zone.tooltip, { sticky: true, className: "map-zone-tooltip" });
        }
      }

      // Update zone label
      const existingLabel = labelMarkers.get(zone.id);
      if (existingLabel) {
        if (!updateZoneLabelMarker(existingLabel, zone, hook.canvasWidth, hook.canvasHeight)) {
          existingLabel.remove();
          labelMarkers.delete(zone.id);
        }
      } else if (zone.name) {
        const label = createZoneLabelMarker(zone, hook.canvasWidth, hook.canvasHeight);
        if (label) {
          label.addTo(hook.zoneLayer);
          labelMarkers.set(zone.id, label);
        }
      }

      reapplyZoneOrder();
      if (hook.layerHandler) hook.layerHandler.rebuildFog();
    });

    hook.handleEvent("zone_vertices_updated", (zone) => {
      const polygon = polygons.get(zone.id);
      if (polygon) {
        polygon.zoneData = zone;
        updateZoneVertices(polygon, zone.vertices, hook.canvasWidth, hook.canvasHeight);
      }

      // Reposition label to new centroid
      const label = labelMarkers.get(zone.id);
      if (label) updateZoneLabelMarker(label, zone, hook.canvasWidth, hook.canvasHeight);

      if (hook.layerHandler) hook.layerHandler.rebuildFog();
    });

    hook.handleEvent("zone_deleted", ({ id }) => {
      const polygon = polygons.get(id);
      if (polygon) {
        polygon.remove();
        polygons.delete(id);
      }

      const label = labelMarkers.get(id);
      if (label) {
        label.remove();
        labelMarkers.delete(id);
      }

      if (hook.layerHandler) hook.layerHandler.rebuildFog();
    });
  }

  /** Highlights the selected zone, un-highlights all others. Shows vertex editor if in edit mode (and not locked). */
  function selectZone(zoneId) {
    vertexEditor.hide();

    for (const [id, polygon] of polygons) {
      const selected = id === zoneId;
      setZoneSelected(polygon, selected);
      if (selected && hook.editMode && !polygon.zoneData.locked) {
        vertexEditor.show(polygon);
      }
    }
  }

  /** Clears selection highlight from all zones. Hides vertex editor. */
  function deselectAll() {
    vertexEditor.hide();

    for (const polygon of polygons.values()) {
      setZoneSelected(polygon, false);
    }
  }

  /** Returns the polygon for a given zone ID. */
  function getPolygon(zoneId) {
    return polygons.get(zoneId);
  }

  // ---------------------------------------------------------------------------
  // Search highlight helpers
  // ---------------------------------------------------------------------------

  /** Sets a single zone's dimmed state. */
  function setDimmed(zoneId, dimmed) {
    const polygon = polygons.get(zoneId);
    if (!polygon) return;
    const opacity = polygon.zoneData?.opacity ?? 0.3;
    polygon.setStyle({
      opacity: dimmed ? 0.15 : 0.8,
      fillOpacity: dimmed ? 0.05 : opacity,
    });
  }

  /** Dims or un-dims all zones. */
  function setAllDimmed(dimmed) {
    for (const polygon of polygons.values()) {
      const opacity = polygon.zoneData?.opacity ?? 0.3;
      polygon.setStyle({
        opacity: dimmed ? 0.15 : 0.8,
        fillOpacity: dimmed ? 0.05 : opacity,
      });
    }
  }

  /** Clears all dimming (restores default opacity). */
  function clearDimming() {
    for (const polygon of polygons.values()) {
      const opacity = polygon.zoneData?.opacity ?? 0.3;
      polygon.setStyle({ opacity: 0.8, fillOpacity: opacity });
    }
  }

  /** Pans/zooms the map to fit a zone's bounds. */
  function focusZone(zoneId) {
    const polygon = polygons.get(zoneId);
    if (!polygon) return;
    hook.leafletMap.flyToBounds(polygon.getBounds(), {
      animate: true,
      duration: 0.5,
      padding: [50, 50],
    });
  }

  function getMaxPosition() {
    let max = 0;
    for (const p of polygons.values()) max = Math.max(max, p.zoneData.position || 0);
    return max;
  }

  function getMinPosition() {
    let min = 0;
    for (const p of polygons.values()) min = Math.min(min, p.zoneData.position || 0);
    return min;
  }

  /** Recalculates all polygon vertices and label positions from stored percentage coords (after canvas resize). */
  function repositionAll() {
    for (const polygon of polygons.values()) {
      const zone = polygon.zoneData;
      const latLngs = (zone.vertices || []).map((v) =>
        toLatLng(v.x, v.y, hook.canvasWidth, hook.canvasHeight),
      );
      polygon.setLatLngs(latLngs);

      // Reposition label to new centroid
      const label = labelMarkers.get(zone.id);
      if (label && latLngs.length > 0) {
        const sum = latLngs.reduce(
          (acc, ll) => ({ lat: acc.lat + ll.lat, lng: acc.lng + ll.lng }),
          { lat: 0, lng: 0 },
        );
        label.setLatLng(L.latLng(sum.lat / latLngs.length, sum.lng / latLngs.length));
      }
    }
  }

  return {
    init,
    destroy,
    renderZones,
    repositionAll,
    selectZone,
    deselectAll,
    getPolygon,
    polygons,
    cancelDrawing,
    setDimmed,
    setAllDimmed,
    clearDimming,
    focusZone,
  };
}
