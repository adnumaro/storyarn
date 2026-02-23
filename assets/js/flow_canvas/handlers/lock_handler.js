/**
 * Lock handling for collaborative node editing.
 * Shows visual indicators when nodes are locked by other users.
 */

/**
 * Creates the lock handler with methods bound to the hook context.
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {Object} Handler methods
 */
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
      const emailName = lockInfo.user_email?.split("@")[0] || "User";

      lockEl.innerHTML = `
        <svg width="12" height="12" viewBox="0 0 20 20" fill="${lockInfo.user_color}">
          <path fill-rule="evenodd" d="M10 1a4.5 4.5 0 0 0-4.5 4.5V9H5a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-.5V5.5A4.5 4.5 0 0 0 10 1Zm3 8V5.5a3 3 0 1 0-6 0V9h6Z" clip-rule="evenodd"/>
        </svg>
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
        border: 1px solid ${lockInfo.user_color};
        border-radius: 12px;
        font-size: 10px;
        color: ${lockInfo.user_color};
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
  };
}
