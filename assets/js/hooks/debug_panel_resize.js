/**
 * DebugPanelResize hook — drag-to-resize for the debug panel.
 *
 * Attaches mousedown on the drag handle, tracks mousemove/mouseup on
 * the document to resize the panel. Height is clamped to 150–500px
 * and persisted to localStorage.
 */

const STORAGE_KEY = "storyarn-debug-panel-height";
const MIN_HEIGHT = 150;
const MAX_HEIGHT = 500;
const DEFAULT_HEIGHT = 280;

export const DebugPanelResize = {
  mounted() {
    this.panel = this.el;
    this.handle = this.el.querySelector("[data-resize-handle]");
    if (!this.handle) return;

    // Load saved height
    const saved = parseInt(localStorage.getItem(STORAGE_KEY), 10);
    const initial = saved >= MIN_HEIGHT && saved <= MAX_HEIGHT ? saved : DEFAULT_HEIGHT;
    this.panel.style.height = `${initial}px`;

    this.dragging = false;
    this.startY = 0;
    this.startHeight = 0;

    this._onMouseDown = (e) => {
      e.preventDefault();
      this.dragging = true;
      this.startY = e.clientY;
      this.startHeight = this.panel.offsetHeight;
      document.body.style.cursor = "row-resize";
      document.body.style.userSelect = "none";
    };

    this._onMouseMove = (e) => {
      if (!this.dragging) return;
      // Dragging up (negative deltaY) → larger panel
      const deltaY = this.startY - e.clientY;
      const newHeight = Math.min(MAX_HEIGHT, Math.max(MIN_HEIGHT, this.startHeight + deltaY));
      this.panel.style.height = `${newHeight}px`;
    };

    this._onMouseUp = () => {
      if (!this.dragging) return;
      this.dragging = false;
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
      // Persist
      const height = this.panel.offsetHeight;
      localStorage.setItem(STORAGE_KEY, String(height));
    };

    this.handle.addEventListener("mousedown", this._onMouseDown);
    document.addEventListener("mousemove", this._onMouseMove);
    document.addEventListener("mouseup", this._onMouseUp);
  },

  destroyed() {
    if (this.handle) {
      this.handle.removeEventListener("mousedown", this._onMouseDown);
    }
    document.removeEventListener("mousemove", this._onMouseMove);
    document.removeEventListener("mouseup", this._onMouseUp);
  },
};
