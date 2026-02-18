/**
 * Pin rendering utilities for the map canvas.
 *
 * Creates Leaflet divIcon markers styled with Lucide icons.
 */

import L from "leaflet";
import { createElement, MapPin, User, Zap, Star, Lock } from "lucide";
import { toLatLng } from "./coordinate_utils.js";
import { sanitizeColor } from "./color_utils.js";

// Pin type → Lucide icon mapping
const PIN_ICONS = {
  location: MapPin,
  character: User,
  event: Zap,
  custom: Star,
};

// Pin size → pixel dimensions
const PIN_SIZES = {
  sm: { icon: 20, anchor: 10 },
  md: { icon: 28, anchor: 14 },
  lg: { icon: 36, anchor: 18 },
};

const DEFAULT_COLOR = "#3b82f6";
const SELECTED_RING_CLASS = "map-pin-selected";

/** Escapes a string for safe injection into innerHTML. */
function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

/**
 * Creates a Leaflet marker for a pin.
 * @param {Object} pin - Pin data from server
 * @param {number} w - Canvas width
 * @param {number} h - Canvas height
 * @param {Object} [opts] - Options
 * @param {boolean} [opts.canEdit=true] - Whether the pin should be draggable
 * @returns {L.Marker}
 */
export function createPinMarker(pin, w, h, opts = {}) {
  const canEdit = opts.canEdit !== undefined ? opts.canEdit : true;
  const pos = toLatLng(pin.position_x, pin.position_y, w, h);
  const color = pin.color || DEFAULT_COLOR;
  const sizeKey = pin.size || "md";
  const dims = PIN_SIZES[sizeKey] || PIN_SIZES.md;

  const icon = L.divIcon({
    className: "map-pin-marker",
    html: buildPinHtml(pin, color, dims),
    iconSize: [dims.icon, dims.icon],
    iconAnchor: [dims.anchor, dims.anchor],
  });

  const marker = L.marker(pos, {
    icon,
    draggable: canEdit,
    title: escapeHtml(pin.label || ""),
  });

  // Store pin data on the marker for easy access
  marker.pinData = pin;

  // Tooltip on hover (bindTooltip with a string uses textContent internally, but
  // we escape for safety in case of future changes)
  if (pin.tooltip) {
    marker.bindTooltip(escapeHtml(pin.tooltip), { className: "map-pin-tooltip" });
  }

  return marker;
}

/**
 * Updates a marker's icon to reflect changed pin data.
 */
export function updatePinMarker(marker, pin) {
  marker.pinData = pin;
  const color = pin.color || DEFAULT_COLOR;
  const sizeKey = pin.size || "md";
  const dims = PIN_SIZES[sizeKey] || PIN_SIZES.md;

  const icon = L.divIcon({
    className: "map-pin-marker",
    html: buildPinHtml(pin, color, dims),
    iconSize: [dims.icon, dims.icon],
    iconAnchor: [dims.anchor, dims.anchor],
  });

  marker.setIcon(icon);

  // Update tooltip
  marker.unbindTooltip();
  if (pin.tooltip) {
    marker.bindTooltip(escapeHtml(pin.tooltip), { className: "map-pin-tooltip" });
  }
}

/**
 * Adds or removes the selection ring on a pin marker.
 */
export function setPinSelected(marker, selected) {
  const el = marker.getElement();
  if (!el) return;

  if (selected) {
    el.classList.add(SELECTED_RING_CLASS);
  } else {
    el.classList.remove(SELECTED_RING_CLASS);
  }
}

// Pre-create lock badge icon at module level (outerHTML for innerHTML context)
const LOCK_BADGE_ICON = createElement(Lock, { width: 8, height: 8, color: "#fff", "stroke-width": 3 }).outerHTML;
const LOCK_BADGE = `<div style="position:absolute;top:-4px;right:-4px;width:14px;height:14px;background:#64748b;border-radius:50%;display:flex;align-items:center;justify-content:center;pointer-events:none">${LOCK_BADGE_ICON}</div>`;

/**
 * Builds the HTML content for a pin's divIcon.
 * Priority: icon_asset_url (custom upload) > avatar_url (sheet) > initials > Lucide icon.
 */
function buildPinHtml(pin, color, dims) {
  const safeColor = sanitizeColor(color);
  let inner;

  if (pin.icon_asset_url) {
    inner = buildIconAssetPinHtml(pin, safeColor, dims);
  } else if (pin.avatar_url) {
    inner = buildAvatarPinHtml(pin, safeColor, dims);
  } else if (pin.sheet_id && !pin.avatar_url) {
    inner = buildInitialsPinHtml(pin, safeColor, dims);
  } else {
    const IconClass = PIN_ICONS[pin.pin_type] || PIN_ICONS.location;
    const iconSize = Math.round(dims.icon * 0.55);
    const iconEl = createElement(IconClass, {
      width: iconSize,
      height: iconSize,
      color: "#fff",
      "stroke-width": 2.5,
    });

    const wrapper = document.createElement("div");
    wrapper.style.cssText = `
      width: ${dims.icon}px;
      height: ${dims.icon}px;
      background: ${safeColor};
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 2px 6px rgba(0,0,0,0.3);
      cursor: grab;
    `;
    wrapper.appendChild(iconEl);
    inner = wrapper.outerHTML;
  }

  if (pin.locked) {
    return `<div style="position:relative">${inner}${LOCK_BADGE}</div>`;
  }

  return inner;
}

/** Builds a pin with a circular avatar image. */
function buildAvatarPinHtml(pin, color, dims) {
  const size = dims.icon + 4;
  const safeUrl = encodeURI(pin.avatar_url);
  return `<div style="width:${size}px;height:${size}px;border-radius:50%;border:2px solid ${color};overflow:hidden;box-shadow:0 2px 6px rgba(0,0,0,0.3);cursor:grab;background:${color}">
    <img src="${safeUrl}" style="width:100%;height:100%;object-fit:cover;border-radius:50%" />
  </div>`;
}

/** Builds a pin with a custom uploaded icon image. */
function buildIconAssetPinHtml(pin, color, dims) {
  const size = dims.icon + 4;
  const safeUrl = encodeURI(pin.icon_asset_url);
  return `<div style="width:${size}px;height:${size}px;border-radius:50%;border:2px solid ${color};overflow:hidden;box-shadow:0 2px 6px rgba(0,0,0,0.3);cursor:grab;background:${color};display:flex;align-items:center;justify-content:center">
    <img src="${safeUrl}" style="width:${dims.icon}px;height:${dims.icon}px;object-fit:contain;border-radius:50%" />
  </div>`;
}

/** Builds a pin with initials (sheet linked but no avatar). */
function buildInitialsPinHtml(pin, color, dims) {
  const initials = escapeHtml((pin.label || "?").slice(0, 2).toUpperCase());
  const fontSize = Math.round(dims.icon * 0.38);
  return `<div style="width:${dims.icon}px;height:${dims.icon}px;background:${color};border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,0.3);cursor:grab">
    <span style="color:#fff;font-size:${fontSize}px;font-weight:600;line-height:1">${initials}</span>
  </div>`;
}
