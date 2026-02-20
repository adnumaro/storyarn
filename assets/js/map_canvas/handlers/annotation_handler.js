/**
 * Annotation handler factory for the map canvas.
 *
 * Manages annotation rendering, creation (in Annotation mode), dragging, and selection.
 */

import L from "leaflet";
import {
  createAnnotationMarker,
  setAnnotationSelected,
  updateAnnotationMarker,
} from "../annotation_renderer.js";
import {
  bringToFrontItem,
  deleteItem,
  editPropertiesItem,
  lockToggleItem,
  sendToBackItem,
} from "../context_menu_builder.js";
import { toLatLng, toPercent } from "../coordinate_utils.js";

const DRAG_DEBOUNCE_MS = 300;

/**
 * Creates the annotation handler attached to the hook instance.
 * @param {Object} hook - The MapCanvas hook instance
 * @param {Object} i18n - Translated label strings
 */
export function createAnnotationHandler(hook, i18n = {}) {
  const markers = new Map();
  // Per-annotation drag debounce timers (annotation ID → timeout handle)
  const dragTimers = new Map();

  function init() {
    renderAnnotations();
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

  function renderAnnotations() {
    const annotations = (hook.mapData.annotations || [])
      .slice()
      .sort((a, b) => (a.position || 0) - (b.position || 0));
    for (const annotation of annotations) {
      addAnnotationToMap(annotation);
    }
  }

  function addAnnotationToMap(annotation) {
    const canEdit = hook.editMode !== false;
    const marker = createAnnotationMarker(annotation, hook.canvasWidth, hook.canvasHeight, {
      canEdit,
    });

    // Click → select
    marker.on("click", (e) => {
      L.DomEvent.stopPropagation(e);
      hook.pushEvent("select_element", { type: "annotation", id: annotation.id });
    });

    // Right-click → context menu
    marker.on("contextmenu", (e) => {
      L.DomEvent.stopPropagation(e);
      L.DomEvent.preventDefault(e);
      if (!hook.contextMenu || !hook.editMode) return;

      const containerPoint = hook.leafletMap.latLngToContainerPoint(e.latlng);
      const data = marker.annotationData;

      const items = [
        editPropertiesItem("annotation", annotation.id, hook, i18n),
        { separator: true },
        bringToFrontItem("annotation", annotation.id, getMaxPosition(), hook, i18n),
        sendToBackItem("annotation", annotation.id, getMinPosition(), hook, i18n),
        { separator: true },
        lockToggleItem("annotation", annotation.id, data.locked, hook, i18n),
      ];

      if (!data.locked) {
        items.push({ separator: true });
        items.push(deleteItem("annotation", annotation.id, hook, i18n));
      }

      hook.contextMenu.show(containerPoint.x, containerPoint.y, items);
    });

    // Double-click → inline text editing
    marker.on("dblclick", (e) => {
      L.DomEvent.stopPropagation(e);
      if (!hook.editMode || annotation.locked) return;
      enableInlineEditing(marker);
    });

    // Drag start → hide floating toolbar
    marker.on("dragstart", () => {
      hook.floatingToolbar?.setDragging(true);
    });

    // Drag end → persist position
    marker.on("dragend", () => {
      hook.floatingToolbar?.setDragging(false);
      const pos = toPercent(marker.getLatLng(), hook.canvasWidth, hook.canvasHeight);
      const annId = annotation.id;
      if (dragTimers.has(annId)) clearTimeout(dragTimers.get(annId));
      dragTimers.set(
        annId,
        setTimeout(() => {
          dragTimers.delete(annId);
          hook.pushEvent("move_annotation", {
            id: String(marker.annotationData.id),
            position_x: pos.x,
            position_y: pos.y,
          });
        }, DRAG_DEBOUNCE_MS),
      );
    });

    marker.addTo(hook.annotationLayer);
    marker.setZIndexOffset((annotation.position || 0) * 10);
    if (annotation.locked) marker.dragging.disable();
    markers.set(annotation.id, marker);
  }

  function setupMapClickHandler() {
    hook.leafletMap.on("click", (e) => {
      if (hook.currentTool !== "annotation") return;

      const pos = toPercent(e.latlng, hook.canvasWidth, hook.canvasHeight);
      hook.pushEvent("create_annotation", {
        position_x: pos.x,
        position_y: pos.y,
      });
    });
  }

  function wireServerEvents() {
    hook.handleEvent("annotation_created", (annotation) => {
      addAnnotationToMap(annotation);
    });

    hook.handleEvent("annotation_updated", (annotation) => {
      const marker = markers.get(annotation.id);
      if (marker) {
        updateAnnotationMarker(marker, annotation);
        marker.setZIndexOffset((annotation.position || 0) * 10);

        // Toggle dragging based on lock state
        if (annotation.locked || !hook.editMode) {
          marker.dragging.disable();
        } else if (hook.editMode) {
          marker.dragging.enable();
        }
      }
    });

    hook.handleEvent("annotation_deleted", ({ id }) => {
      const marker = markers.get(id);
      if (marker) {
        marker.remove();
        markers.delete(id);
      }
    });
  }

  function selectAnnotation(annotationId) {
    for (const [id, marker] of markers) {
      setAnnotationSelected(marker, id === annotationId);
    }
  }

  function deselectAll() {
    for (const marker of markers.values()) {
      setAnnotationSelected(marker, false);
    }
  }

  // ---------------------------------------------------------------------------
  // Search highlight helpers
  // ---------------------------------------------------------------------------

  /** Sets a single annotation's dimmed state. */
  function setDimmed(annotationId, dimmed) {
    const marker = markers.get(annotationId);
    if (!marker) return;
    const el = marker.getElement();
    if (el) el.style.opacity = dimmed ? "0.2" : "1";
  }

  /** Dims or un-dims all annotations. */
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

  /** Pans the map to center on an annotation. */
  function focusAnnotation(annotationId) {
    const marker = markers.get(annotationId);
    if (!marker) return;
    hook.leafletMap.flyTo(marker.getLatLng(), hook.leafletMap.getZoom(), {
      animate: true,
      duration: 0.5,
    });
  }

  /** Enables or disables dragging on all existing annotation markers. Respects locked state. */
  function setEditMode(enabled) {
    for (const marker of markers.values()) {
      if (enabled && !marker.annotationData.locked) {
        marker.dragging.enable();
      } else {
        marker.dragging.disable();
      }
    }
  }

  function getMaxPosition() {
    let max = 0;
    for (const m of markers.values()) max = Math.max(max, m.annotationData.position || 0);
    return max;
  }

  function getMinPosition() {
    let min = 0;
    for (const m of markers.values()) min = Math.min(min, m.annotationData.position || 0);
    return min;
  }

  /**
   * Enables contentEditable inline editing on an annotation marker's text div.
   * On blur or Enter: pushes the updated text to the server and restores normal state.
   */
  function enableInlineEditing(marker) {
    if (!marker) return;
    const el = marker.getElement();
    if (!el) return;

    const textDiv = el.querySelector("[data-annotation-text]");
    if (!textDiv) return;

    // Already editing?
    if (textDiv.contentEditable === "true") return;

    textDiv.contentEditable = "true";
    textDiv.style.cursor = "text";
    textDiv.style.outline = "none";
    textDiv.focus();

    // Select all text
    const range = document.createRange();
    range.selectNodeContents(textDiv);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);

    // Disable marker dragging during editing
    if (marker.dragging) marker.dragging.disable();

    const finishEditing = () => {
      textDiv.contentEditable = "false";
      textDiv.style.cursor = "";
      textDiv.removeEventListener("blur", onBlur);
      textDiv.removeEventListener("keydown", onKeyDown);

      const newText = textDiv.textContent || "";
      hook.pushEvent("update_annotation", {
        id: String(marker.annotationData.id),
        field: "text",
        value: newText,
      });

      // Re-enable dragging if not locked
      if (marker.dragging && hook.editMode && !marker.annotationData.locked) {
        marker.dragging.enable();
      }
    };

    const onBlur = () => finishEditing();
    const onKeyDown = (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        textDiv.blur();
      }
      if (e.key === "Escape") {
        // Revert text to original
        textDiv.textContent = marker.annotationData.text || "";
        textDiv.contentEditable = "false";
        textDiv.style.cursor = "";
        textDiv.removeEventListener("blur", onBlur);
        textDiv.removeEventListener("keydown", onKeyDown);
        if (marker.dragging && hook.editMode && !marker.annotationData.locked) {
          marker.dragging.enable();
        }
      }
    };

    textDiv.addEventListener("blur", onBlur);
    textDiv.addEventListener("keydown", onKeyDown);
  }

  /** Recalculates all marker positions from stored percentage coords (after canvas resize). */
  function repositionAll() {
    for (const marker of markers.values()) {
      const ann = marker.annotationData;
      marker.setLatLng(
        toLatLng(ann.position_x, ann.position_y, hook.canvasWidth, hook.canvasHeight),
      );
    }
  }

  return {
    init,
    destroy,
    renderAnnotations,
    repositionAll,
    selectAnnotation,
    deselectAll,
    setDimmed,
    setAllDimmed,
    clearDimming,
    focusAnnotation,
    setEditMode,
    enableInlineEditing,
    markers,
  };
}
