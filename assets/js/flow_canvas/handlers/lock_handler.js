/**
 * Lock handling for collaborative node editing.
 * Shows visual indicators when nodes are locked by other users.
 */
import { Lock } from "lucide";
import { createIconHTML } from "../node_config.js";

const LOCK_ICON = createIconHTML(Lock, { size: 12 });

/**
 * Creates the lock handler with methods bound to the hook context.
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {Object} Handler methods
 */
function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function sanitizeColor(color) {
  return /^#[0-9a-fA-F]{3,8}$/.test(color) ? color : "#888";
}

export function createLockHandler(hook) {
  return {
    /**
     * Initializes lock state from server data.
     */
    init() {
      const container = hook.el;
      hook.nodeLocks = JSON.parse(container.dataset.locks || "{}");
    },

    /**
     * Handles lock state update from server.
     * @param {Object} data - Lock data with locks map
     */
    handleLocksUpdated(data) {
      hook.nodeLocks = data.locks || {};
      this.updateLockIndicators();
    },

    /**
     * Updates visual lock indicators on all nodes.
     */
    updateLockIndicators() {
      for (const [nodeId, node] of hook.nodeMap.entries()) {
        const lockInfo = hook.nodeLocks[nodeId];
        const nodeEl = hook.area.nodeViews.get(node.id)?.element;
        if (!nodeEl) continue;

        // Remove existing lock indicator
        const existingLock = nodeEl.querySelector(".node-lock-indicator");
        if (existingLock) existingLock.remove();

        // Add lock indicator if locked by another user
        if (lockInfo && lockInfo.user_id !== hook.currentUserId) {
          const lockEl = this.createLockIndicator(lockInfo);
          nodeEl.style.position = "relative";
          nodeEl.appendChild(lockEl);
        }
      }
    },

    /**
     * Creates a lock indicator element.
     * @param {Object} lockInfo - Lock info with user_email, user_color, user_id
     * @returns {HTMLElement} The lock indicator element
     */
    createLockIndicator(lockInfo) {
      const lockEl = document.createElement("div");
      lockEl.className = "node-lock-indicator";
      const emailName = escapeHtml(lockInfo.user_email?.split("@")[0] || "User");
      const safeColor = sanitizeColor(lockInfo.user_color);

      lockEl.innerHTML = `
        <span style="color: ${safeColor};">${LOCK_ICON}</span>
        <span>${emailName}</span>
      `;

      lockEl.style.cssText = `
        position: absolute;
        top: -8px;
        right: -8px;
        display: flex;
        align-items: center;
        gap: 4px;
        padding: 2px 6px;
        background: var(--color-base-100, white);
        border: 1px solid ${safeColor};
        border-radius: 12px;
        font-size: 10px;
        color: ${safeColor};
        font-family: system-ui, sans-serif;
        z-index: 10;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      `;

      return lockEl;
    },

    /**
     * Checks if a node is locked by another user.
     * @param {string|number} nodeId - The node ID to check
     * @returns {boolean} True if locked by another user
     */
    isNodeLocked(nodeId) {
      const lockInfo = hook.nodeLocks[nodeId];
      return lockInfo && lockInfo.user_id !== hook.currentUserId;
    },

    /**
     * Keeps FlowCanvas teardown symmetrical with the rest of the handlers.
     * Lock indicators are rebuilt from server state, so no explicit cleanup is needed.
     */
    destroy() {},
  };
}
