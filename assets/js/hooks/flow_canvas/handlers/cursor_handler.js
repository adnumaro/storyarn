/**
 * Cursor handling for real-time collaboration.
 * Manages local cursor broadcasting and remote cursor display.
 */

/**
 * Creates the cursor handler with methods bound to the hook context.
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {Object} Handler methods
 */
export function createCursorHandler(hook) {
  return {
    /**
     * Initializes cursor tracking infrastructure.
     */
    init() {
      hook.remoteCursors = new Map();
      hook.lastCursorSend = 0;
      hook.cursorThrottleMs = 50;

      // Create cursor overlay container
      hook.cursorOverlay = document.createElement("div");
      hook.cursorOverlay.className = "cursor-overlay";
      hook.cursorOverlay.style.cssText =
        "position: absolute; inset: 0; pointer-events: none; z-index: 100;";
      hook.el.appendChild(hook.cursorOverlay);

      // Bind mouse move handler
      hook.mouseMoveHandler = (e) => this.handleMouseMove(e);
      hook.el.addEventListener("mousemove", hook.mouseMoveHandler);
    },

    /**
     * Handles local mouse movement and broadcasts cursor position.
     * @param {MouseEvent} e - The mouse event
     */
    handleMouseMove(e) {
      const now = Date.now();
      if (now - hook.lastCursorSend < hook.cursorThrottleMs) return;
      hook.lastCursorSend = now;

      const rect = hook.el.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      const transform = hook.area.area.transform;
      const canvasX = (x - transform.x) / transform.k;
      const canvasY = (y - transform.y) / transform.k;

      hook.pushEvent("cursor_moved", { x: canvasX, y: canvasY });
    },

    /**
     * Handles incoming cursor update from another user.
     * @param {Object} data - Cursor data with user_id, x, y, user_email, user_color
     */
    handleCursorUpdate(data) {
      if (data.user_id === hook.currentUserId) return;

      let cursorEl = hook.remoteCursors.get(data.user_id);
      if (!cursorEl) {
        cursorEl = this.createRemoteCursor(data);
        hook.remoteCursors.set(data.user_id, cursorEl);
        hook.cursorOverlay.appendChild(cursorEl);
      }

      const transform = hook.area.area.transform;
      const screenX = data.x * transform.k + transform.x;
      const screenY = data.y * transform.k + transform.y;

      cursorEl.style.transform = `translate(${screenX}px, ${screenY}px)`;
      cursorEl.style.opacity = "1";

      if (cursorEl._fadeTimer) clearTimeout(cursorEl._fadeTimer);
      cursorEl._fadeTimer = setTimeout(() => {
        cursorEl.style.opacity = "0.3";
      }, 3000);
    },

    /**
     * Handles cursor leave event when a user disconnects.
     * @param {Object} data - Data with user_id
     */
    handleCursorLeave(data) {
      const cursorEl = hook.remoteCursors.get(data.user_id);
      if (cursorEl) {
        cursorEl.remove();
        hook.remoteCursors.delete(data.user_id);
      }
    },

    /**
     * Creates a DOM element for a remote user's cursor.
     * @param {Object} data - User data with user_email, user_color
     * @returns {HTMLElement} The cursor element
     */
    createRemoteCursor(data) {
      const cursor = document.createElement("div");
      cursor.className = "remote-cursor";
      cursor.style.cssText = `
        position: absolute;
        top: 0;
        left: 0;
        pointer-events: none;
        transition: transform 0.05s linear, opacity 0.3s ease;
        z-index: 100;
      `;

      const emailName = data.user_email?.split("@")[0] || "User";

      cursor.innerHTML = `
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" style="filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));">
          <path d="M5.5 3.21V20.8c0 .45.54.67.85.35l4.86-4.86a.5.5 0 0 1 .35-.15h6.87c.48 0 .72-.58.38-.92L6.35 2.86a.5.5 0 0 0-.85.35Z" fill="${data.user_color}" stroke="white" stroke-width="1.5"/>
        </svg>
        <span style="
          position: absolute;
          top: 20px;
          left: 12px;
          background: ${data.user_color};
          color: white;
          font-size: 10px;
          padding: 2px 6px;
          border-radius: 4px;
          white-space: nowrap;
          font-family: system-ui, sans-serif;
        ">${emailName}</span>
      `;

      return cursor;
    },

    /**
     * Cleans up cursor resources.
     */
    destroy() {
      if (hook.mouseMoveHandler) {
        hook.el.removeEventListener("mousemove", hook.mouseMoveHandler);
      }

      for (const cursor of hook.remoteCursors.values()) {
        if (cursor._fadeTimer) clearTimeout(cursor._fadeTimer);
      }

      if (hook.cursorOverlay) {
        hook.cursorOverlay.remove();
      }
    },
  };
}
