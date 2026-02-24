/**
 * Annotation rendering utilities for the map canvas.
 *
 * Creates Leaflet divIcon markers styled as text labels.
 */

import L from "leaflet";
import { createElement, Lock } from "lucide";
import { sanitizeColor } from "./color_utils.js";
import { toLatLng } from "./coordinate_utils.js";

// Font size → CSS values
const FONT_SIZES = {
  sm: { fontSize: "11px", padding: "2px 6px" },
  md: { fontSize: "14px", padding: "4px 8px" },
  lg: { fontSize: "16px", padding: "5px 10px" },
};

const DEFAULT_COLOR = "#fbbf24";

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
  const color = sanitizeColor(annotation.color || DEFAULT_COLOR);
  const sizeKey = annotation.font_size || "md";
  const dims = FONT_SIZES[sizeKey] || FONT_SIZES.md;
  const text = escapeHtml(annotation.text || "");
  const lockPrefix = annotation.locked ? LOCK_ICON_SVG : "";

  // Post-it style: wrapper holds the clipped body + the solid fold triangle
  const fold = 12;
  return (
    `<div class="map-annotation-label" style="position:relative;cursor:grab;min-width:120px;max-width:300px;">` +
    // Body with clipped top-right corner
    `<div style="` +
    `font-size:${dims.fontSize};padding:${dims.padding};padding-right:calc(${dims.padding.split(" ")[1] || dims.padding} + ${fold}px);` +
    `background:${color};opacity:0.55;position:absolute;inset:0;` +
    `clip-path:polygon(0 0, calc(100% - ${fold}px) 0, 100% ${fold}px, 100% 100%, 0 100%);` +
    `"></div>` +
    // Text layer (same padding, transparent bg)
    `<div data-annotation-text style="` +
    `position:relative;` +
    `font-size:${dims.fontSize};padding:${dims.padding};padding-right:calc(${dims.padding.split(" ")[1] || dims.padding} + ${fold}px);` +
    `color:#111827;font-weight:600;line-height:1.3;white-space:pre-wrap;` +
    `">${lockPrefix}${text}</div>` +
    // Fold triangle — solid color, sits at top-right
    `<span style="` +
    `position:absolute;top:0;right:0;` +
    `width:${fold}px;height:${fold}px;` +
    `background:${color};` +
    `clip-path:polygon(0 0, 100% 100%, 0 100%);` +
    `"></span>` +
    `</div>`
  );
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}
