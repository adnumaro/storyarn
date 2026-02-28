import { pushWithTarget } from "../utils/event_dispatcher";

/**
 * TableRowSortable — custom pointer-event drag-and-drop for table rows.
 *
 * Vertical reorder only, triggered by .row-drag-handle grip.
 * Pushes "reorder_table_rows" with { block_id, row_ids } on drop.
 */
export const TableRowSortable = {
  mounted() {
    this._drag = null;
    this._ptr = { x: 0, y: 0 };
    this._scrollParent = null;
    this._scrollRaf = null;
    this._preview = null;

    this._onDown = this._pointerDown.bind(this);
    this._onMove = this._pointerMove.bind(this);
    this._onUp = this._pointerUp.bind(this);

    this.el.addEventListener("pointerdown", this._onDown);

    this._ind = Object.assign(document.createElement("div"), {
      className: "dnd-indicator",
    });
    document.body.appendChild(this._ind);
  },

  updated() {},

  destroyed() {
    this.el.removeEventListener("pointerdown", this._onDown);
    this._ind.remove();
    this._cleanup();
  },

  // ── Pointer handlers ──────────────────────────────────────────────────────

  _pointerDown(e) {
    if (e.button > 0 && e.pointerType === "mouse") return;
    if (!e.target.closest(".row-drag-handle")) return;

    const row = e.target.closest("[data-row-id]");
    if (!row || !this.el.contains(row)) return;

    e.preventDefault();

    this._drag = {
      el: row,
      startY: e.clientY,
      active: false,
      drop: null,
    };

    document.addEventListener("pointermove", this._onMove);
    document.addEventListener("pointerup", this._onUp);
    document.addEventListener("pointercancel", this._onUp);
  },

  _pointerMove(e) {
    if (!this._drag) return;
    this._ptr = { x: e.clientX, y: e.clientY };

    if (!this._drag.active) {
      if (Math.abs(e.clientY - this._drag.startY) < 5) return;
      this._startDrag();
    }

    this._updatePreview(e.clientY);
    this._updateIndicator(e.clientY);
  },

  _pointerUp() {
    if (!this._drag) return;
    if (this._drag.active && this._drag.drop) this._applyDrop();
    this._cleanup();
  },

  // ── Drag lifecycle ────────────────────────────────────────────────────────

  _startDrag() {
    this._drag.active = true;
    this._drag.el.classList.add("dnd-dragging");
    document.body.classList.add("dnd-active");
    this._scrollParent = this._findScrollParent(this.el);
    this._preview = this._createPreview(this._drag.el);
    this._startAutoScroll();
  },

  _cleanup() {
    document.removeEventListener("pointermove", this._onMove);
    document.removeEventListener("pointerup", this._onUp);
    document.removeEventListener("pointercancel", this._onUp);

    this._drag?.el?.classList.remove("dnd-dragging");
    document.body.classList.remove("dnd-active");
    this._preview?.remove();
    this._preview = null;
    this._ind.style.display = "none";
    this._cancelAutoScroll();
    this._drag = null;
  },

  // ── Drag preview ──────────────────────────────────────────────────────────

  _createPreview(row) {
    const r = row.getBoundingClientRect();
    const el = row.cloneNode(true);
    el.removeAttribute("id");
    for (const child of el.querySelectorAll("[id]")) child.removeAttribute("id");

    Object.assign(el.style, {
      position: "fixed",
      width: `${r.width}px`,
      height: `${r.height}px`,
      top: `${r.top}px`,
      left: `${r.left}px`,
      opacity: "0.8",
      pointerEvents: "none",
      zIndex: "9998",
      boxShadow: "0 4px 12px rgba(0,0,0,0.1)",
      background: "var(--fallback-b1,oklch(var(--b1)))",
      display: "table-row",
    });

    // Wrap in a table so the row renders correctly
    const table = document.createElement("table");
    Object.assign(table.style, {
      position: "fixed",
      width: `${r.width}px`,
      top: `${r.top}px`,
      left: `${r.left}px`,
      opacity: "0.8",
      pointerEvents: "none",
      zIndex: "9998",
      boxShadow: "0 4px 12px rgba(0,0,0,0.1)",
      borderCollapse: "collapse",
    });
    table.appendChild(el);
    document.body.appendChild(table);
    return table;
  },

  _updatePreview(y) {
    if (!this._preview) return;
    const r = this._drag.el.getBoundingClientRect();
    this._preview.style.top = `${y - r.height / 2}px`;
  },

  // ── Hit-testing & indicator ───────────────────────────────────────────────

  _updateIndicator(y) {
    const drop = this._findDrop(y);
    this._drag.drop = drop;

    if (!drop) {
      this._ind.style.display = "none";
      return;
    }

    this._ind.style.display = "block";
    const r = drop.el.getBoundingClientRect();
    const s = this._ind.style;
    s.top = `${drop.edge === "top" ? r.top - 1 : r.bottom - 1}px`;
    s.left = `${r.left}px`;
    s.width = `${r.width}px`;
    s.height = "3px";
  },

  _findDrop(y) {
    const rows = this.el.querySelectorAll("[data-row-id]");
    for (const row of rows) {
      if (row === this._drag.el) continue;
      const r = row.getBoundingClientRect();
      if (y < r.top || y > r.bottom) continue;
      const edge = (y - r.top) / r.height < 0.5 ? "top" : "bottom";
      return { el: row, edge };
    }
    return null;
  },

  // ── Drop application ──────────────────────────────────────────────────────

  _applyDrop() {
    const { el: target, edge } = this._drag.drop;
    const draggedId = this._drag.el.dataset.rowId;

    const rows = Array.from(this.el.querySelectorAll("[data-row-id]"));
    const ids = rows.map((r) => r.dataset.rowId).filter((id) => id !== draggedId);

    const targetIdx = ids.indexOf(target.dataset.rowId);
    const insertIdx = edge === "top" ? targetIdx : targetIdx + 1;
    ids.splice(insertIdx, 0, draggedId);

    pushWithTarget(this, "reorder_table_rows", {
      block_id: this.el.dataset.blockId,
      row_ids: ids,
    });
  },

  // ── Auto-scroll ───────────────────────────────────────────────────────────

  _findScrollParent(el) {
    let cur = el.parentElement;
    while (cur) {
      const { overflow, overflowY } = getComputedStyle(cur);
      if (/auto|scroll/.test(overflow + overflowY)) return cur;
      cur = cur.parentElement;
    }
    return document.documentElement;
  },

  _cancelAutoScroll() {
    if (!this._scrollRaf) return;
    cancelAnimationFrame(this._scrollRaf);
    this._scrollRaf = null;
  },

  _startAutoScroll() {
    const margin = 80;
    const speed = 0.3;
    const tick = () => {
      if (!this._drag?.active) return;
      const { y } = this._ptr;
      const sp = this._scrollParent;
      if (y < margin) sp.scrollTop -= (margin - y) * speed;
      if (y > window.innerHeight - margin) sp.scrollTop += (y - (window.innerHeight - margin)) * speed;
      this._scrollRaf = requestAnimationFrame(tick);
    };
    this._scrollRaf = requestAnimationFrame(tick);
  },
};
