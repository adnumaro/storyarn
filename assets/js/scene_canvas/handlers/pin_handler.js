/**
 * Pin handler factory for the map canvas.
 *
 * Manages pin rendering, creation (in Pin mode), dragging, and selection.
 */

import L from "leaflet";
import {
  bringToFrontItem,
  deleteItem,
  editPropertiesItem,
  lockToggleItem,
  sendToBackItem,
} from "../context_menu_builder.js";
import { toLatLng, toPercent } from "../coordinate_utils.js";
import { createPinMarker, setPinSelected, updatePinMarker } from "../pin_renderer.js";

const DRAG_DEBOUNCE_MS = 300;

/**
 * Creates the pin handler attached to the hook instance.
 * @param {Object} hook - The SceneCanvas hook instance
 * @param {Object} i18n - Translated label strings
 * @returns {{ init(), destroy(), renderPins(), handlePinCreated(pin), handlePinUpdated(pin) }}
 */
export function createPinHandler(hook, i18n = {}) {
  // Map of pin ID → L.Marker
  const markers = new Map();
  // Per-pin drag debounce timers (pin ID → timeout handle)
  const dragTimers = new Map();

  function init() {
    renderPins();
    setupMapClickHandler();
    wireServerEvents();
  }

  function destroy() {
    for (const timer of dragTimers.values()) {
      clearTimeout(timer);
    }
    dragTimers.clear();
    markers.clear();
  }

  /** Renders all initial pins from sceneData, sorted by position for z-ordering. */
  function renderPins() {
    const pins = (hook.sceneData.pins || [])
      .slice()
      .sort((a, b) => (a.position || 0) - (b.position || 0));
    for (const pin of pins) {
      addPinToMap(pin);
    }
  }

  /** Adds a single pin marker to the Leaflet map. */
  function addPinToMap(pin) {
    const canEdit = hook.editMode !== false;
    const marker = createPinMarker(pin, hook.canvasWidth, hook.canvasHeight, { canEdit });

    // Click → select or connect
    marker.on("click", (e) => {
      L.DomEvent.stopPropagation(e);

      if (hook.currentTool === "connector" && hook.connectionHandler) {
        hook.connectionHandler.handlePinClickInConnectMode(pin.id);
      } else {
        hook.pushEvent("select_element", { type: "pin", id: pin.id });
      }
    });

    // Hover feedback for connector mode
    marker.on("mouseover", () => {
      if (hook.connectionHandler) {
        hook.connectionHandler.handlePinMouseOver(pin.id);
      }
    });

    marker.on("mouseout", () => {
      if (hook.connectionHandler) {
        hook.connectionHandler.handlePinMouseOut(pin.id);
      }
    });

    // Right-click → context menu
    marker.on("contextmenu", (e) => {
      L.DomEvent.stopPropagation(e);
      L.DomEvent.preventDefault(e);
      if (!hook.contextMenu || !hook.editMode) return;

      const containerPoint = hook.leafletMap.latLngToContainerPoint(e.latlng);
      const items = [
        editPropertiesItem("pin", pin.id, hook, i18n),
        {
          label: i18n.connect_to || "Connect To\u2026",
          action: () => {
            hook.pushEvent("set_tool", { tool: "connector" });
            hook.connectionHandler.handlePinClickInConnectMode(pin.id);
          },
        },
        { separator: true },
        bringToFrontItem("pin", pin.id, getMaxPosition(), hook, i18n),
        sendToBackItem("pin", pin.id, getMinPosition(), hook, i18n),
        { separator: true },
        lockToggleItem("pin", pin.id, marker.pinData.locked, hook, i18n),
      ];

      // Only show destructive items if not locked
      if (!marker.pinData.locked) {
        items.push({ separator: true });
        items.push(deleteItem("pin", pin.id, hook, i18n));
      }

      hook.contextMenu.show(containerPoint.x, containerPoint.y, items);
    });

    // Drag start → hide floating toolbar
    marker.on("dragstart", () => {
      hook.floatingToolbar?.setDragging(true);
    });

    // Drag → update connected lines in real time
    marker.on("drag", () => {
      if (hook.connectionHandler) {
        hook.connectionHandler.updateEndpointsForPin(pin.id);
      }
    });

    // Drag end → persist position
    marker.on("dragend", () => {
      hook.floatingToolbar?.setDragging(false);
      // Final endpoint sync
      if (hook.connectionHandler) {
        hook.connectionHandler.updateEndpointsForPin(pin.id);
      }

      const pos = toPercent(marker.getLatLng(), hook.canvasWidth, hook.canvasHeight);
      const pinId = pin.id;
      if (dragTimers.has(pinId)) clearTimeout(dragTimers.get(pinId));
      dragTimers.set(
        pinId,
        setTimeout(() => {
          dragTimers.delete(pinId);
          hook.pushEvent("move_pin", {
            id: String(marker.pinData.id),
            position_x: pos.x,
            position_y: pos.y,
          });
        }, DRAG_DEBOUNCE_MS),
      );
    });

    marker.addTo(hook.pinLayer);
    marker.setZIndexOffset((pin.position || 0) * 10);
    if (pin.locked) marker.dragging.disable();
    markers.set(pin.id, marker);
  }

  /** Handles click on the map canvas to create a new pin (when in Pin mode). */
  function setupMapClickHandler() {
    hook.leafletMap.on("click", (e) => {
      if (hook.currentTool !== "pin") return;

      const pos = toPercent(e.latlng, hook.canvasWidth, hook.canvasHeight);

      if (hook.pendingSheetForPin) {
        hook.pushEvent("create_pin_from_sheet", {
          position_x: pos.x,
          position_y: pos.y,
        });
      } else {
        hook.pushEvent("create_pin", {
          position_x: pos.x,
          position_y: pos.y,
        });
      }
    });
  }

  /** Wires handleEvent listeners from the server. */
  function wireServerEvents() {
    hook.handleEvent("pin_created", (pin) => {
      addPinToMap(pin);
    });

    hook.handleEvent("pin_updated", (pin) => {
      const marker = markers.get(pin.id);
      if (marker) {
        updatePinMarker(marker, pin);
        marker.setZIndexOffset((pin.position || 0) * 10);

        // Toggle dragging based on lock state
        if (pin.locked || !hook.editMode) {
          marker.dragging.disable();
        } else if (hook.editMode) {
          marker.dragging.enable();
        }
      }
    });

    hook.handleEvent("pin_deleted", ({ id }) => {
      const marker = markers.get(id);
      if (marker) {
        marker.remove();
        markers.delete(id);
      }
    });
  }

  /** Highlights the selected pin, un-highlights all others. */
  function selectPin(pinId) {
    for (const [id, marker] of markers) {
      setPinSelected(marker, id === pinId);
    }
  }

  /** Clears selection highlight from all pins. */
  function deselectAll() {
    for (const marker of markers.values()) {
      setPinSelected(marker, false);
    }
  }

  // ---------------------------------------------------------------------------
  // Search highlight helpers
  // ---------------------------------------------------------------------------

  /** Sets a single pin's dimmed state. */
  function setDimmed(pinId, dimmed) {
    const marker = markers.get(pinId);
    if (!marker) return;
    const el = marker.getElement();
    if (el) el.style.opacity = dimmed ? "0.2" : "1";
  }

  /** Dims or un-dims all pins. */
  function setAllDimmed(dimmed) {
    for (const marker of markers.values()) {
      const el = marker.getElement();
      if (el) el.style.opacity = dimmed ? "0.2" : "1";
    }
  }

  /** Clears all dimming (restores default opacity). */
  function clearDimming() {
    for (const marker of markers.values()) {
      const el = marker.getElement();
      if (el) el.style.opacity = "";
    }
  }

  /** Pans the map to center on a pin and flashes it. */
  function focusPin(pinId) {
    const marker = markers.get(pinId);
    if (!marker) return;

    hook.leafletMap.flyTo(marker.getLatLng(), hook.leafletMap.getZoom(), {
      animate: true,
      duration: 0.5,
    });

    const el = marker.getElement();
    if (el) {
      el.classList.add("map-element-flash");
      setTimeout(() => el.classList.remove("map-element-flash"), 1500);
    }
  }

  /** Enables or disables dragging on all existing pin markers. Respects locked state. */
  function setEditMode(enabled) {
    for (const marker of markers.values()) {
      if (enabled && !marker.pinData.locked) {
        marker.dragging.enable();
      } else {
        marker.dragging.disable();
      }
    }
  }

  function getMaxPosition() {
    let max = 0;
    for (const m of markers.values()) max = Math.max(max, m.pinData.position || 0);
    return max;
  }

  function getMinPosition() {
    let min = 0;
    for (const m of markers.values()) min = Math.min(min, m.pinData.position || 0);
    return min;
  }

  /** Recalculates all marker positions from stored percentage coords (after canvas resize). */
  function repositionAll() {
    for (const marker of markers.values()) {
      const pin = marker.pinData;
      marker.setLatLng(
        toLatLng(pin.position_x, pin.position_y, hook.canvasWidth, hook.canvasHeight),
      );
    }
  }

  return {
    init,
    destroy,
    renderPins,
    repositionAll,
    selectPin,
    deselectAll,
    setDimmed,
    setAllDimmed,
    clearDimming,
    focusPin,
    setEditMode,
    markers,
  };
}
