/**
 * Lock handling for collaborative scene editing.
 * Shows visual indicators when elements are locked by other users.
 */

import L from "leaflet";
import { createElement, Lock } from "lucide";

/**
 * Creates the lock handler for the scene canvas.
 * @param {Object} hook - The SceneCanvas hook instance
 * @returns {Object} Handler methods
 */
export function createLockHandler(hook) {
  const lockIndicators = new Map(); // entity_id → L.marker
  let lockLayer = null;

  return {
    /**
     * Initializes lock state from server data.
     */
    init() {
      lockLayer = L.layerGroup();
      lockLayer.addTo(hook.leafletMap);
      hook.entityLocks = JSON.parse(hook.el.dataset.locks || "{}");
    },

    /**
     * Handles lock state update from server.
     * @param {Object} data - { locks: { entity_id: lock_info } }
     */
    handleLocksUpdated(data) {
      hook.entityLocks = data.locks || {};
      this.updateLockIndicators();
    },

    /**
     * Updates visual lock indicators on canvas elements.
     */
    updateLockIndicators() {
      // Remove stale indicators
      for (const [id, indicator] of lockIndicators) {
        if (!hook.entityLocks[id]) {
          indicator.remove();
          lockIndicators.delete(id);
        }
      }

      // Add indicators for new locks by other users
      for (const [entityId, lockInfo] of Object.entries(hook.entityLocks)) {
        if (lockInfo.user_id === hook.currentUserId) continue;
        if (lockIndicators.has(entityId)) continue;

        const latLng = findElementLatLng(hook, entityId);
        if (!latLng) continue;

        const indicator = L.marker(latLng, {
          icon: createLockIcon(lockInfo),
          interactive: false,
          zIndexOffset: 9000,
        });
        indicator.addTo(lockLayer);
        lockIndicators.set(entityId, indicator);
      }
    },

    /**
     * Checks if an element is locked by another user.
     * @param {string|number} entityId - The entity ID to check
     * @returns {boolean}
     */
    isLocked(entityId) {
      const id = String(entityId);
      const lock = hook.entityLocks[id];
      return lock && lock.user_id !== hook.currentUserId;
    },

    /**
     * Cleans up lock resources.
     */
    destroy() {
      for (const [, indicator] of lockIndicators) indicator.remove();
      lockIndicators.clear();
      lockLayer?.remove();
      lockLayer = null;
    },
  };
}

/**
 * Finds the Leaflet LatLng for a canvas element by its ID.
 * Searches pins, then zones (centroid), then annotations.
 */
function findElementLatLng(hook, entityId) {
  const id = parseInt(entityId, 10);

  // Check pins
  if (hook.pinHandler) {
    const marker = hook.pinHandler.markers?.get(id);
    if (marker) return marker.getLatLng();
  }

  // Check zones (use centroid)
  if (hook.zoneHandler) {
    const polygon = hook.zoneHandler.polygons?.get(id);
    if (polygon) return polygon.getBounds().getCenter();
  }

  // Check annotations
  if (hook.annotationHandler) {
    const marker = hook.annotationHandler.markers?.get(id);
    if (marker) return marker.getLatLng();
  }

  return null;
}

// Pre-create lock icon SVG at module level
const LOCK_ICON = createElement(Lock, { width: 12, height: 12 }).outerHTML;

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

/**
 * Creates a Leaflet DivIcon for a lock indicator.
 * @param {Object} lockInfo - { user_email, user_color }
 * @returns {L.DivIcon}
 */
function createLockIcon(lockInfo) {
  const name = escapeHtml(lockInfo.user_email?.split("@")[0] || "User");
  const c = safeColor(lockInfo.user_color);

  return L.divIcon({
    className: "element-lock-indicator",
    iconSize: [0, 0],
    iconAnchor: [0, 24],
    html: `
      <div style="
        display: flex;
        align-items: center;
        gap: 4px;
        padding: 2px 6px;
        background: var(--color-base-100, white);
        border: 1px solid ${c};
        border-radius: 12px;
        font-size: 10px;
        color: ${c};
        font-family: system-ui, sans-serif;
        white-space: nowrap;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        pointer-events: none;
      ">
        ${LOCK_ICON}
        <span>${name}</span>
      </div>
    `,
  });
}
