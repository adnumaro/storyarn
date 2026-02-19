/**
 * Floating toolbar positioning module for the map canvas.
 *
 * Manages showing/hiding and positioning the toolbar div above the
 * selected element. JS only writes style.left, style.top, and a CSS
 * class for visibility — LiveView patches the toolbar's children (content).
 *
 * IMPORTANT: We never set `display` or other inline styles that LiveView
 * also controls, because morphdom patches would overwrite them on re-render.
 * Instead we toggle the `.toolbar-visible` class, and CSS handles the rest
 * (opacity + pointer-events + transform).
 *
 * @param {Object} hook - The MapCanvas hook instance
 * @returns {{ show(type, id), hide(), reposition(), setDragging(bool) }}
 */

import L from "leaflet";

export function createFloatingToolbar(hook) {
  const MARGIN = 8;
  const TOOLBAR_OFFSET_Y = 12; // gap between element and toolbar bottom edge

  let currentType = null;
  let currentId = null;
  let isDragging = false;

  /**
   * Shows the toolbar for the given element.
   * Called after the server pushes "element_selected".
   */
  function show(type, id) {
    currentType = type;
    currentId = id;
    isDragging = false;

    // Give LiveView a tick to patch the toolbar content before positioning
    requestAnimationFrame(() => {
      position();
    });
  }

  /** Hides the toolbar. */
  function hide() {
    currentType = null;
    currentId = null;

    const el = getToolbarEl();
    if (el) {
      el.classList.remove("toolbar-visible");
    }
  }

  /** Repositions the toolbar for the current selection (e.g. on pan/zoom). */
  function reposition() {
    if (!currentType || !currentId || isDragging) return;
    position();
  }

  /** Hides during drag, repositions on drag end. */
  function setDragging(dragging) {
    isDragging = dragging;
    const el = getToolbarEl();
    if (!el) return;

    if (dragging) {
      el.classList.remove("toolbar-visible");
    } else if (currentType && currentId) {
      requestAnimationFrame(() => position());
    }
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  function getToolbarEl() {
    return document.getElementById("floating-toolbar-content");
  }

  /**
   * Computes the screen position of the selected element and places
   * the toolbar above it (or below if too close to the top edge).
   */
  function position() {
    const el = getToolbarEl();
    if (!el || !currentType || !currentId) return;

    const map = hook.leafletMap;
    if (!map) return;

    const latlng = getElementLatLng(currentType, currentId);
    if (!latlng) {
      el.classList.remove("toolbar-visible");
      return;
    }

    const containerPoint = map.latLngToContainerPoint(latlng);

    // Temporarily make visible to measure, using visibility: hidden so it
    // takes up layout space but isn't shown on screen
    const wasVisible = el.classList.contains("toolbar-visible");
    if (!wasVisible) {
      el.style.visibility = "hidden";
      el.style.opacity = "0";
      el.style.pointerEvents = "auto";
      el.classList.add("toolbar-visible");
    }

    const toolbarRect = el.getBoundingClientRect();
    const toolbarW = toolbarRect.width;
    const toolbarH = toolbarRect.height;

    // Canvas container bounds
    const canvas = hook.el;
    const canvasRect = canvas.getBoundingClientRect();

    // Position above the element, centered horizontally
    let left = containerPoint.x - toolbarW / 2;
    let top = containerPoint.y - toolbarH - TOOLBAR_OFFSET_Y;

    // Element-specific vertical offsets
    if (currentType === "pin") {
      top -= 20; // above pin icon
    } else if (currentType === "annotation") {
      top -= 10;
    }

    // Clamp horizontally
    left = Math.max(MARGIN, Math.min(left, canvasRect.width - toolbarW - MARGIN));

    // If toolbar would go above the canvas, flip below the element
    if (top < MARGIN) {
      top = containerPoint.y + TOOLBAR_OFFSET_Y + 20;
    }

    el.style.left = `${Math.round(left)}px`;
    el.style.top = `${Math.round(top)}px`;

    // Clear the temporary inline overrides and let the CSS class take effect
    el.style.visibility = "";
    el.style.opacity = "";
    el.style.pointerEvents = "";
    el.classList.add("toolbar-visible");
  }

  /**
   * Gets the Leaflet LatLng for the selected element so we can project
   * it to screen coordinates.
   */
  function getElementLatLng(type, id) {
    switch (type) {
      case "pin": {
        const marker = hook.pinHandler?.markers?.get(id);
        return marker ? marker.getLatLng() : null;
      }
      case "zone": {
        const polygon = hook.zoneHandler?.getPolygon?.(id);
        if (!polygon) return null;
        // Use center of the north (top) edge of the bounding box
        const bounds = polygon.getBounds();
        return bounds.getNorthWest().equals(bounds.getNorthEast())
          ? bounds.getCenter()
          : L.latLng(bounds.getNorth(), (bounds.getWest() + bounds.getEast()) / 2);
      }
      case "annotation": {
        const marker = hook.annotationHandler?.markers?.get(id);
        return marker ? marker.getLatLng() : null;
      }
      case "connection": {
        const line = hook.connectionHandler?.lines?.get(id);
        if (!line) return null;
        // Midpoint of the polyline
        const latLngs = line.getLatLngs();
        if (latLngs.length === 0) return null;
        if (latLngs.length === 1) return latLngs[0];
        const mid = Math.floor(latLngs.length / 2);
        // Interpolate between mid-1 and mid for even count
        if (latLngs.length % 2 === 0) {
          const a = latLngs[mid - 1];
          const b = latLngs[mid];
          return L.latLng((a.lat + b.lat) / 2, (a.lng + b.lng) / 2);
        }
        return latLngs[mid];
      }
      default:
        return null;
    }
  }

  return { show, hide, reposition, setDragging };
}
