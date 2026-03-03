/**
 * DebugVarsResize hook — resizable columns for the debug variables table.
 *
 * Drag the handle on the right edge of each <th> to resize columns.
 * Widths are persisted to localStorage (no server round-trips).
 * Restored on mount and after every LiveView patch (updated()).
 */

const STORAGE_KEY = "storyarn-debug-vars-cols";
const MIN_COL_WIDTH = 60;
const DEFAULT_WIDTHS = {
  variable: 180,
  type: 82,
  initial: 80,
  previous: 80,
  current: 96,
};

export const DebugVarsResize = {
  mounted() {
    this._drag = null;
    this._applyWidths();

    this._onMouseDown = this._onMouseDown.bind(this);
    this._onMouseMove = this._onMouseMove.bind(this);
    this._onMouseUp = this._onMouseUp.bind(this);

    this.el.addEventListener("mousedown", this._onMouseDown);
    document.addEventListener("mousemove", this._onMouseMove);
    document.addEventListener("mouseup", this._onMouseUp);
  },

  updated() {
    // LiveView patches reset col widths — restore from localStorage
    this._applyWidths();
    if (this._drag) this._cleanup();
  },

  destroyed() {
    this.el.removeEventListener("mousedown", this._onMouseDown);
    document.removeEventListener("mousemove", this._onMouseMove);
    document.removeEventListener("mouseup", this._onMouseUp);
  },

  _loadWidths() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {};
    } catch {
      return {};
    }
  },

  _applyWidths() {
    const saved = this._loadWidths();
    this.el.querySelectorAll("col[data-col-id]").forEach((col) => {
      const id = col.dataset.colId;
      const width = saved[id] || DEFAULT_WIDTHS[id];
      if (width) col.style.width = `${width}px`;
    });
  },

  _onMouseDown(e) {
    const handle = e.target.closest("[data-col-resize]");
    if (!handle) return;

    e.preventDefault();

    const colId = handle.dataset.colResize;
    const col = this.el.querySelector(`col[data-col-id="${colId}"]`);
    if (!col) return;

    const startX = e.clientX;
    const startWidth = parseInt(col.style.width, 10) || DEFAULT_WIDTHS[colId] || 100;

    this._drag = { col, colId, startX, startWidth };
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";
  },

  _onMouseMove(e) {
    if (!this._drag) return;
    const { col, startX, startWidth } = this._drag;
    const width = Math.max(MIN_COL_WIDTH, startWidth + (e.clientX - startX));
    col.style.width = `${width}px`;
  },

  _onMouseUp(e) {
    if (!this._drag) return;
    const { colId, startX, startWidth } = this._drag;
    const width = Math.max(MIN_COL_WIDTH, startWidth + (e.clientX - startX));

    const saved = this._loadWidths();
    saved[colId] = width;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(saved));

    this._cleanup();
  },

  _cleanup() {
    document.body.style.cursor = "";
    document.body.style.userSelect = "";
    this._drag = null;
  },
};
