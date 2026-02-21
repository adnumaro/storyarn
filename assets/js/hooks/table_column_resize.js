/**
 * TableColumnResize hook — mounted on <table>.
 *
 * Drag column border handles to resize. Widths are applied to <col> elements
 * inside <colgroup> so the browser enforces the width via table-fixed layout.
 *
 * During drag: pure client-side (zero server round-trips).
 * On mouseup: pushEvent("resize_table_column", {column-id, width}).
 */

const MIN_WIDTH = 80;

export const TableColumnResize = {
  mounted() {
    this._onMouseDown = this._onMouseDown.bind(this);
    this._onMouseMove = this._onMouseMove.bind(this);
    this._onMouseUp = this._onMouseUp.bind(this);

    this.el.addEventListener("mousedown", this._onMouseDown);
    this._drag = null;
  },

  updated() {
    // If LiveView patched the DOM mid-drag, abort.
    if (this._drag) this._cleanup();
  },

  destroyed() {
    this._cleanup();
    this.el.removeEventListener("mousedown", this._onMouseDown);
  },

  // ── Event handlers ──────────────────────────────────────────────────

  _onMouseDown(e) {
    const handle = e.target.closest("[data-resize-handle]");
    if (!handle) return;

    e.preventDefault();

    const colId = handle.dataset.colId;
    const col = this.el.querySelector(`col[data-col-id="${colId}"]`);
    if (!col) return;

    const startX = e.clientX;
    const startWidth = parseInt(col.style.width, 10) || 150;

    this._drag = { col, colId, startX, startWidth };

    document.addEventListener("mousemove", this._onMouseMove);
    document.addEventListener("mouseup", this._onMouseUp);
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";
  },

  _calcWidth(clientX) {
    const { startX, startWidth } = this._drag;
    return Math.max(MIN_WIDTH, startWidth + (clientX - startX));
  },

  _onMouseMove(e) {
    if (!this._drag) return;
    this._drag.col.style.width = `${this._calcWidth(e.clientX)}px`;
  },

  _onMouseUp(e) {
    if (!this._drag) return;

    const { colId, startWidth } = this._drag;
    const width = this._calcWidth(e.clientX);

    // Only persist if width actually changed
    if (width !== startWidth) {
      const target = this.el.dataset.phxTarget;
      if (target) {
        this.pushEventTo(target, "resize_table_column", {
          "column-id": colId,
          width,
        });
      } else {
        this.pushEvent("resize_table_column", {
          "column-id": colId,
          width,
        });
      }
    }

    this._cleanup();
  },

  // ── Helpers ─────────────────────────────────────────────────────────

  _cleanup() {
    document.removeEventListener("mousemove", this._onMouseMove);
    document.removeEventListener("mouseup", this._onMouseUp);
    document.body.style.cursor = "";
    document.body.style.userSelect = "";
    this._drag = null;
  },
};
