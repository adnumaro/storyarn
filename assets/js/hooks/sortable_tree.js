/**
 * SortableTree — custom pointer-event drag-and-drop for sidebar trees.
 *
 * Drop zones (Notion-style):
 *  - Top 25%: indicator line → insert before (reorder)
 *  - Middle 50%: highlight → nest as last child
 *  - Bottom 25%: indicator line → insert after (last sibling only)
 *
 * Features: auto-scroll, auto-expand collapsed nodes on 600ms hover.
 * No DOM moves — LiveView patches the tree after the push event.
 */
export const SortableTree = {
  mounted() {
    this._drag = null;
    this._ptr = { x: 0, y: 0 };
    this._scrollParent = null;
    this._scrollRaf = null;
    this._preview = null;
    this._highlightTarget = null;
    this._expandTimer = null;
    this._expandTarget = null;
    this.treeType = this.el.dataset.treeType || "sheets";

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

    const item = e.target.closest("[data-item-id]");
    if (!item?.classList.contains("cursor-grab")) return;
    if (!this.el.contains(item)) return;
    if (e.target.closest("button, input, .dropdown")) return;

    e.preventDefault();

    this._drag = {
      el: item,
      startX: e.clientX,
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
      const dx = e.clientX - this._drag.startX;
      const dy = e.clientY - this._drag.startY;
      if (Math.abs(dx) < 5 && Math.abs(dy) < 5) return;
      this._startDrag();
    }

    this._updatePreview(e.clientX, e.clientY);
    this._updateIndicator(e.clientX, e.clientY);
    this._checkAutoExpand();
  },

  _pointerUp() {
    if (!this._drag) return;

    if (!this._drag.active) {
      this._drag.el.querySelector(".group\\/item a")?.click();
      this._cleanup();
      return;
    }

    if (this._drag.drop) this._applyDrop();
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
    this._highlightTarget?.classList.remove("dnd-drop-target");
    this._highlightTarget = null;
    this._clearExpandTimer();
    this._cancelAutoScroll();
    this._drag = null;
  },

  // ── Drag preview ──────────────────────────────────────────────────────────

  _createPreview(item) {
    const row = item.querySelector(".group\\/item");
    if (!row) return null;

    const r = row.getBoundingClientRect();
    const el = row.cloneNode(true);
    el.removeAttribute("id");
    for (const child of el.querySelectorAll("[id]")) child.removeAttribute("id");

    Object.assign(el.style, {
      position: "fixed",
      width: `${r.width}px`,
      top: `${r.top}px`,
      left: `${r.left}px`,
      opacity: "0.8",
      pointerEvents: "none",
      zIndex: "9998",
      boxShadow: "0 8px 24px rgba(0,0,0,0.12)",
      transform: "scale(1.01)",
      borderRadius: "0.5rem",
    });
    document.body.appendChild(el);
    return el;
  },

  _updatePreview(x, y) {
    if (!this._preview) return;
    const row = this._drag.el.querySelector(".group\\/item");
    if (!row) return;
    const r = row.getBoundingClientRect();
    this._preview.style.top = `${y - r.height / 2}px`;
    this._preview.style.left = `${r.left}px`;
  },

  // ── Hit-testing & indicator ───────────────────────────────────────────────

  _updateIndicator(x, y) {
    const drop = this._findDrop(x, y);
    this._drag.drop = drop;

    this._highlightTarget?.classList.remove("dnd-drop-target");
    this._highlightTarget = null;

    if (!drop) {
      this._ind.style.display = "none";
      return;
    }

    if (drop.zone !== "center") {
      this._ind.style.display = "block";
      this._placeIndicator(drop);
      return;
    }

    this._ind.style.display = "none";
    const row = drop.el.querySelector(".group\\/item");
    if (!row) return;
    row.classList.add("dnd-drop-target");
    this._highlightTarget = row;
  },

  _findDrop(x, y) {
    const hit = document.elementFromPoint(x, y);
    if (!hit) return null;

    let cur = hit;
    while (cur && cur !== document.body) {
      const id = cur.dataset?.itemId;
      if (id && this.el.contains(cur) && cur !== this._drag.el && !this._drag.el.contains(cur)) {
        const zone = this._getZone(cur, y);
        if (zone) return { el: cur, zone };
      }
      cur = cur.parentElement;
    }
    return null;
  },

  _getZone(item, y) {
    const row = item.querySelector(".group\\/item");
    if (!row) return "top";

    const r = row.getBoundingClientRect();
    const ratio = (y - r.top) / r.height;

    if (ratio < 0.25) return "top";
    if (ratio > 1) return null;
    if (this._isLastSibling(item) && ratio > 0.75) return "bottom";
    return "center";
  },

  _isLastSibling(item) {
    const container = item.parentElement;
    if (!container?.hasAttribute("data-sortable-container")) return true;
    const siblings = container.querySelectorAll(":scope > [data-item-id]");
    return siblings[siblings.length - 1] === item;
  },

  _placeIndicator(drop) {
    const row = drop.el.querySelector(".group\\/item");
    if (!row) return;

    const r = row.getBoundingClientRect();
    const panel = this.el.closest("#tree-panel");
    const pb = panel?.getBoundingClientRect();
    const right = pb ? Math.min(r.right, pb.right) : r.right;
    const s = this._ind.style;

    s.top = `${drop.zone === "top" ? r.top - 1 : r.bottom - 1}px`;
    s.left = `${r.left}px`;
    s.width = `${right - r.left}px`;
    s.height = "3px";
  },

  // ── Auto-expand collapsed nodes on hover ──────────────────────────────────

  _checkAutoExpand() {
    const drop = this._drag?.drop;
    if (!drop || drop.zone !== "center") return this._clearExpandTimer();

    const target = drop.el;
    if (!target.classList.contains("tree-node")) return this._clearExpandTimer();

    const content = target.querySelector("[data-sortable-container]");
    if (!content?.classList.contains("hidden")) return this._clearExpandTimer();
    if (this._expandTarget === target) return;

    this._clearExpandTimer();
    this._expandTarget = target;
    this._expandTimer = setTimeout(() => {
      const toggle = target.querySelector("[phx-hook='TreeToggle']");
      if (toggle) toggle.click();
      this._expandTarget = null;
    }, 600);
  },

  _clearExpandTimer() {
    if (!this._expandTimer) return;
    clearTimeout(this._expandTimer);
    this._expandTimer = null;
    this._expandTarget = null;
  },

  // ── Drop application ──────────────────────────────────────────────────────

  _applyDrop() {
    const draggedId = this._drag.el.dataset.itemId;
    const { el: target, zone } = this._drag.drop;

    const { parentId, position } =
      zone === "center"
        ? this._nestPosition(target, draggedId)
        : this._siblingPosition(target, zone, draggedId);

    const isSheets = this.treeType === "sheets";

    this.pushEvent(isSheets ? "move_sheet" : "move_to_parent", {
      [isSheets ? "sheet_id" : "item_id"]: draggedId,
      [isSheets ? "parent_id" : "new_parent_id"]: String(parentId),
      position: String(position),
    });
  },

  _nestPosition(target, draggedId) {
    const container = target.querySelector("[data-sortable-container]");
    const count = container
      ? Array.from(container.children).filter(
          (el) => el.dataset.itemId && el.dataset.itemId !== draggedId,
        ).length
      : 0;
    return { parentId: target.dataset.itemId, position: count };
  },

  _siblingPosition(target, zone, draggedId) {
    const parentContainer = target.parentElement?.closest("[data-sortable-container]");
    const parentId = parentContainer?.dataset.parentId ?? "";
    const siblings = Array.from(parentContainer?.children ?? []).filter(
      (el) => el.dataset.itemId && el.dataset.itemId !== draggedId,
    );
    const idx = siblings.indexOf(target);
    const position = Math.max(0, zone === "top" ? idx : idx + 1);
    return { parentId, position };
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
      if (y > window.innerHeight - margin)
        sp.scrollTop += (y - (window.innerHeight - margin)) * speed;
      this._scrollRaf = requestAnimationFrame(tick);
    };
    this._scrollRaf = requestAnimationFrame(tick);
  },
};

export default { SortableTree };
