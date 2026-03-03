/**
 * Annotation rendering utilities for the map canvas.
 *
 * Creates Leaflet divIcon markers styled as text labels.
 */

import L from "leaflet";
import { createElement, Lock } from "lucide";
import { isValidHexColor } from "./color_utils.js";
import { toLatLng } from "./coordinate_utils.js";

const VALID_SIZES = new Set(["sm", "md", "lg"]);

function getDefaultColor() {
  return "#fbbf24";
}

/**
 * Creates a Leaflet marker for an annotation.
 * @param {Object} annotation - Annotation data from server
 * @param {number} w - Canvas width
 * @param {number} h - Canvas height
 * @param {Object} [opts] - Options
 * @param {boolean} [opts.canEdit=true] - Whether the annotation is draggable
 * @returns {L.Marker}
 */
export function createAnnotationMarker(annotation, w, h, opts = {}) {
  const canEdit = opts.canEdit !== undefined ? opts.canEdit : true;
  const pos = toLatLng(annotation.position_x, annotation.position_y, w, h);

  const icon = L.divIcon({
    className: "map-annotation-marker",
    html: buildAnnotationHtml(annotation),
    iconSize: null,
    iconAnchor: [0, 0],
  });

  const marker = L.marker(pos, {
    icon,
    draggable: canEdit,
  });

  marker.annotationData = annotation;

  return marker;
}

/**
 * Updates a marker's icon to reflect changed annotation data.
 */
export function updateAnnotationMarker(marker, annotation) {
  marker.annotationData = annotation;

  const icon = L.divIcon({
    className: "map-annotation-marker",
    html: buildAnnotationHtml(annotation),
    iconSize: null,
    iconAnchor: [0, 0],
  });

  marker.setIcon(icon);
}

/**
 * Adds or removes the selection ring on an annotation marker.
 */
export function setAnnotationSelected(marker, selected) {
  const el = marker.getElement();
  if (!el) return;

  if (selected) {
    el.classList.add("map-annotation-selected");
  } else {
    el.classList.remove("map-annotation-selected");
  }
}

// Pre-create lock icon at module level (outerHTML for innerHTML context)
const lockEl = createElement(Lock, { width: 10, height: 10, "stroke-width": 2.5 });
lockEl.style.cssText = "display:inline-block;vertical-align:middle;margin-right:3px;opacity:0.7";
const LOCK_ICON_SVG = lockEl.outerHTML;

/**
 * Builds the HTML content for an annotation's divIcon.
 */
function buildAnnotationHtml(annotation) {
  const color = isValidHexColor(annotation.color) ? annotation.color : getDefaultColor();
  const sizeKey = VALID_SIZES.has(annotation.font_size) ? annotation.font_size : "md";
  const text = escapeHtml(annotation.text || "");
  const lockPrefix = annotation.locked ? LOCK_ICON_SVG : "";

  return (
    `<div class="map-annotation-label map-annotation-${sizeKey}" style="--ann-color:${color}">` +
    `<div class="map-annotation-bg"></div>` +
    `<div data-annotation-text class="map-annotation-text">${lockPrefix}${text}</div>` +
    `<span class="map-annotation-fold"></span>` +
    `</div>`
  );
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}
