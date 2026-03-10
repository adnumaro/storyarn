/**
 * Cursor handling for real-time collaboration on the scene canvas.
 * Manages local cursor broadcasting and remote cursor display using Leaflet markers.
 */

import L from "leaflet";
import { toLatLng, toPercent } from "../coordinate_utils.js";

const THROTTLE_MS = 50;
const FADE_TIMEOUT_MS = 3000;

/**
 * Creates the cursor handler for the scene canvas.
 * @param {Object} hook - The SceneCanvas hook instance
 * @returns {Object} Handler methods
 */
export function createCursorHandler(hook) {
  const remoteCursors = new Map(); // user_id → { marker, fadeTimer }
  let lastSend = 0;
  let cursorLayer = null;

  return {
    /**
     * Initializes cursor tracking: broadcasts local cursor, prepares remote cursor layer.
     */
    init() {
      // Dedicated layer group for remote cursors (above all element layers)
      cursorLayer = L.layerGroup();
      cursorLayer.addTo(hook.leafletMap);

      // Broadcast local cursor position (throttled)
      hook.leafletMap.on("mousemove", (e) => {
        const now = Date.now();
        if (now - lastSend < THROTTLE_MS) return;
        lastSend = now;

        const pct = toPercent(e.latlng, hook.canvasWidth, hook.canvasHeight);
        hook.pushEvent("cursor_moved", { x: pct.x, y: pct.y });
      });

      // Notify server when mouse leaves canvas
      hook.leafletMap
        .getContainer()
        .addEventListener("mouseleave", this._onMouseLeave);
    },

    _onMouseLeave() {
      hook.pushEvent("cursor_left", {});
    },

    /**
     * Handles incoming cursor update from another user.
     * @param {Object} data - { user_id, user_email, user_color, x, y }
     */
    handleCursorUpdate(data) {
      const latLng = toLatLng(data.x, data.y, hook.canvasWidth, hook.canvasHeight);
      let entry = remoteCursors.get(data.user_id);

      if (!entry) {
        const marker = L.marker(latLng, {
          icon: createCursorIcon(data.user_email, data.user_color),
          interactive: false,
          zIndexOffset: 10000,
        });
        marker.addTo(cursorLayer);
        entry = { marker, fadeTimer: null };
        remoteCursors.set(data.user_id, entry);
      } else {
        entry.marker.setLatLng(latLng);
      }

      // Reset fade timer
      const el = entry.marker.getElement();
      if (el) el.style.opacity = "1";

      clearTimeout(entry.fadeTimer);
      entry.fadeTimer = setTimeout(() => {
        const markerEl = entry.marker.getElement();
        if (markerEl) markerEl.style.opacity = "0.3";
      }, FADE_TIMEOUT_MS);
    },

    /**
     * Handles cursor leave event when a user disconnects or leaves the canvas.
     * @param {Object} data - { user_id }
     */
    handleCursorLeave(data) {
      const entry = remoteCursors.get(data.user_id);
      if (entry) {
        clearTimeout(entry.fadeTimer);
        entry.marker.remove();
        remoteCursors.delete(data.user_id);
      }
    },

    /**
     * Cleans up all cursor resources.
     */
    destroy() {
      hook.leafletMap
        ?.getContainer()
        ?.removeEventListener("mouseleave", this._onMouseLeave);

      for (const [, entry] of remoteCursors) {
        clearTimeout(entry.fadeTimer);
        entry.marker.remove();
      }
      remoteCursors.clear();
      cursorLayer?.remove();
      cursorLayer = null;
    },
  };
}

/**
 * Creates a Leaflet DivIcon for a remote user's cursor.
 * @param {string} email - User email (displayed as label)
 * @param {string} color - User color (hex)
 * @returns {L.DivIcon}
 */
/** Escapes HTML special characters to prevent XSS. */
function escapeHtml(str) {
  const el = document.createElement("span");
  el.textContent = str;
  return el.innerHTML;
}

/** Validates a hex color string. Returns fallback if invalid. */
function safeColor(color) {
  return /^#[0-9a-fA-F]{3,8}$/.test(color) ? color : "#888888";
}

function createCursorIcon(email, color) {
  const name = escapeHtml(email?.split("@")[0] || "User");
  const c = safeColor(color);

  return L.divIcon({
    className: "remote-cursor-icon",
    iconSize: [24, 36],
    iconAnchor: [5, 3],
    html: `
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none"
           style="filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3)); position: absolute; top: 0; left: 0;">
        <path d="M5.5 3.21V20.8c0 .45.54.67.85.35l4.86-4.86a.5.5 0 0 1 .35-.15h6.87c.48 0 .72-.58.38-.92L6.35 2.86a.5.5 0 0 0-.85.35Z"
              fill="${c}" stroke="white" stroke-width="1.5"/>
      </svg>
      <span style="
        position: absolute;
        top: 20px;
        left: 12px;
        background: ${c};
        color: white;
        font-size: 10px;
        padding: 2px 6px;
        border-radius: 4px;
        white-space: nowrap;
        font-family: system-ui, sans-serif;
        pointer-events: none;
      ">${name}</span>
    `,
  });
}
