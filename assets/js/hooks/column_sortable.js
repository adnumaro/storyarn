/**
 * ColumnSortable — custom pointer-event drag-and-drop for block lists.
 *
 * Replaces SortableJS with a lightweight custom system:
 *  - Pointer events → works on mouse and touch
 *  - position:fixed indicator line (Notion-style, no ghost placeholder)
 *  - Auto-scroll when cursor approaches viewport edges
 *  - Handles: vertical reorder, column creation, column reorder, escape from column
 *
 * Drop logic: physically moves DOM elements on drop, then calls collectLayout()
 * to build the layout array and push reorder_with_columns to LiveView.
 */
export const ColumnSortable = {
  mounted() {
    this._drag = null; // active drag state
    this._ptr = { x: 0, y: 0 }; // last pointer position
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

  updated() {
    // LiveView patched the DOM — drag is already complete, nothing to rebuild
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this._onDown);
    this._ind.remove();
    this._cleanup();
  },

  // ── Pointer handlers ────────────────────────────────────────────────────────

  _pointerDown(e) {
    if (e.button > 0 && e.pointerType === "mouse") return;
    if (!e.target.closest(".drag-handle")) return;

    const draggable = e.target.closest(".block-wrapper, .column-item");
    if (!draggable || !this.el.contains(draggable)) return;

    e.preventDefault();

    this._drag = {
      el: draggable,
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
  },

  _pointerUp() {
    if (!this._drag) return;
    if (this._drag.active && this._drag.drop) this._applyDrop();
    this._cleanup();
  },

  // ── Drag lifecycle ───────────────────────────────────────────────────────────

  _startDrag() {
    this._drag.active = true;
    this._drag.el.classList.add("dnd-dragging");
    document.body.classList.add("dnd-active");
    this._scrollParent = this._findScrollParent(this.el);
    this._preview = this._createPreview(this._drag.el);
    this._ind.style.display = "block";
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

    if (this._scrollRaf) {
      cancelAnimationFrame(this._scrollRaf);
      this._scrollRaf = null;
    }
    this._drag = null;
  },

  // ── Drag preview ─────────────────────────────────────────────────────────────

  _createPreview(source) {
    const r = this._contentRect(source);
    const el = source.cloneNode(true);
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
    });
    document.body.appendChild(el);
    return el;
  },

  _updatePreview(x, y) {
    if (!this._preview) return;
    const r = this._contentRect(this._drag.el);
    this._preview.style.top = `${y - r.height / 2}px`;
    this._preview.style.left = `${x - r.width / 2}px`;
  },

  // ── Hit-testing & indicator ──────────────────────────────────────────────────

  _updateIndicator(x, y) {
    const drop = this._findDrop(x, y);
    this._drag.drop = drop;
    this._ind.style.display = drop ? "block" : "none";
    if (drop) this._placeIndicator(drop.el, drop.edge);
  },

  _isDropTarget(el) {
    return (
      this.el.contains(el) &&
      (el.classList.contains("block-wrapper") ||
        el.classList.contains("column-group") ||
        el.classList.contains("column-item")) &&
      el !== this._drag.el &&
      !this._drag.el.contains(el)
    );
  },

  _findDrop(x, y) {
    const hit = document.elementFromPoint(x, y);
    if (!hit) return null;
    let cur = hit;
    while (cur && cur !== document.body) {
      if (this._isDropTarget(cur)) return { el: cur, edge: this._getEdge(cur, x, y) };
      cur = cur.parentElement;
    }
    return null;
  },

  // Returns the visual content bounds, accounting for:
  //  - block-wrappers: use inner [data-id] (wrapper extends into negative-margin gutters)
  //  - column-groups: strip horizontal padding (same overflow issue as block-wrappers)
  _contentRect(el) {
    if (el.classList.contains("block-wrapper")) {
      const inner = el.querySelector("[data-id]");
      if (inner) return inner.getBoundingClientRect();
    }
    if (el.classList.contains("column-group")) {
      const { paddingLeft, paddingRight } = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      const pl = parseFloat(paddingLeft);
      const pr = parseFloat(paddingRight);
      return {
        left: r.left + pl,
        right: r.right - pr,
        top: r.top,
        bottom: r.bottom,
        width: r.width - pl - pr,
        height: r.height,
      };
    }
    return el.getBoundingClientRect();
  },

  _getEdge(el, x, y) {
    const r = this._contentRect(el);
    const verticalEdge = () => ((y - r.top) / r.height < 0.5 ? "top" : "bottom");

    if (el.classList.contains("column-item")) {
      return x < r.left + r.width / 2 ? "left" : "right";
    }

    if (el.classList.contains("block-wrapper")) {
      const inner = el.querySelector("[data-id]");
      if (inner?.dataset.blockType !== "table") {
        const relX = (x - r.left) / r.width;
        if (relX < 0.25) return "left";
        if (relX > 0.75) return "right";
      }
    }

    return verticalEdge();
  },

  _placeIndicator(el, edge) {
    const r = this._contentRect(el);
    const s = this._ind.style;

    if (edge === "top" || edge === "bottom") {
      s.top = `${edge === "top" ? r.top - 1 : r.bottom - 1}px`;
      s.left = `${r.left}px`;
      s.width = `${r.width}px`;
      s.height = "3px";
      return;
    }

    const h = r.height * 0.8;
    s.top = `${r.top + (r.height - h) / 2}px`;
    s.height = `${h}px`;
    s.left = `${edge === "left" ? r.left - 5 : r.right + 3}px`;
    s.width = "3px";
  },

  // ── FLIP animation ───────────────────────────────────────────────────────────

  _snapshotPositions() {
    const map = new Map();
    const elements = this.el.querySelectorAll(
      ":scope > .block-wrapper, :scope > .column-group, .column-item",
    );
    for (const el of elements) {
      const r = el.getBoundingClientRect();
      map.set(el, { top: r.top, left: r.left });
    }
    return map;
  },

  _animateFlip(snapshot) {
    const dragged = this._drag.el;
    for (const [el, before] of snapshot) {
      if (el === dragged || el.contains(dragged) || !this.el.contains(el)) continue;

      const after = el.getBoundingClientRect();
      const dy = before.top - after.top;
      const dx = before.left - after.left;
      if (Math.abs(dy) < 1 && Math.abs(dx) < 1) continue;

      el.style.transition = "none";
      el.style.transform = `translate(${dx}px, ${dy}px)`;

      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          el.style.transition = "transform 220ms cubic-bezier(0.25, 0.46, 0.45, 0.94)";
          el.style.transform = "";
          const cleanup = () => {
            el.style.transition = "";
            el.style.transform = "";
            el.removeEventListener("transitionend", cleanup);
          };
          el.addEventListener("transitionend", cleanup);
        });
      });
    }
  },

  // ── Drop application ─────────────────────────────────────────────────────────

  _applyDrop() {
    const snapshot = this._snapshotPositions();
    const { el: dragged } = this._drag;
    const { el: target, edge } = this._drag.drop;

    if (edge === "left" || edge === "right") {
      target.classList.contains("block-wrapper")
        ? this._mergeIntoBlock(dragged, target, edge)
        : this._insertIntoColumn(dragged, target, edge);

      this._animateFlip(snapshot);
      this._sendLayout();

      return;
    }

    const anchor = target.classList.contains("column-item")
      ? target.closest(".column-group")
      : target;
    dragged.classList.contains("column-item")
      ? this._escapeToMain(dragged, anchor, edge)
      : edge === "bottom"
        ? anchor.after(dragged)
        : anchor.before(dragged);

    this._animateFlip(snapshot);
    this._sendLayout();
  },

  // Merge dragged (block-wrapper or column-item) into a block-wrapper target,
  // creating or expanding a column group.
  _mergeIntoBlock(dragged, target, edge) {
    const isBlock = dragged.classList.contains("block-wrapper");
    const sourceGroup = isBlock ? null : dragged.parentElement;
    const content = isBlock ? dragged.querySelector("[data-id]") : dragged;
    edge === "right" ? target.appendChild(content) : target.prepend(content);
    if (isBlock) dragged.remove();
    this._collapseSourceGroup(sourceGroup);
  },

  // Insert dragged (block-wrapper or column-item) adjacent to a column-item target.
  _insertIntoColumn(dragged, target, edge) {
    const isBlock = dragged.classList.contains("block-wrapper");
    const content = isBlock ? dragged.querySelector("[data-id]") : dragged;
    edge === "right" ? target.after(content) : target.before(content);
    if (isBlock) dragged.remove();
  },

  // Move a column-item out of its group into the main container as a full-width block.
  _escapeToMain(dragged, anchor, edge) {
    const sourceGroup = dragged.parentElement;
    const wrapper = this._tempWrapper();
    edge === "bottom" ? anchor.after(wrapper) : anchor.before(wrapper);
    wrapper.appendChild(dragged);
    this._collapseSourceGroup(sourceGroup);
  },

  // After removing an item from a column-group: promote the last remaining item
  // to a full-width block-wrapper, or remove the group if now empty.
  _collapseSourceGroup(group) {
    if (!group?.classList.contains("column-group")) return;
    const remaining = group.querySelectorAll("[data-id]");
    if (remaining.length === 0) {
      group.remove();

      return;
    }

    if (remaining.length === 1) {
      const wrapper = this._tempWrapper();
      group.after(wrapper);
      wrapper.appendChild(remaining[0]);
      group.remove();
    }
  },

  _tempWrapper() {
    const el = document.createElement("div");
    el.className = "block-wrapper flex dnd-dropped";
    return el;
  },

  _sendLayout() {
    const items = this._collectLayout();
    const phxTarget = this.el.dataset.phxTarget;
    phxTarget
      ? this.pushEventTo(phxTarget, "reorder_with_columns", { items })
      : this.pushEvent("reorder_with_columns", { items });
  },

  // ── Layout collection ────────────────────────────────────────────────────────

  _collectLayout() {
    const items = [];
    for (const child of this.el.children) {
      if (child.classList.contains("column-group")) {
        const groupId = child.dataset.columnGroup;
        let idx = 0;
        for (const el of child.querySelectorAll("[data-id]")) {
          items.push({ id: el.dataset.id, column_group_id: groupId, column_index: idx++ });
        }

        continue;
      }

      if (child.classList.contains("block-wrapper")) {
        const blockEls = child.querySelectorAll("[data-id]");
        if (blockEls.length === 1) {
          items.push({ id: blockEls[0].dataset.id, column_group_id: null, column_index: 0 });

          continue;
        }

        if (blockEls.length > 1) {
          const gid = crypto.randomUUID();
          let idx = 0;
          for (const el of blockEls) {
            items.push({ id: el.dataset.id, column_group_id: gid, column_index: idx++ });
          }

          continue;
        }
      }

      if (child.dataset.id) {
        // Escaped column item → treat as full-width
        items.push({ id: child.dataset.id, column_group_id: null, column_index: 0 });
      }
    }

    return items;
  },

  // ── Auto-scroll ──────────────────────────────────────────────────────────────

  _findScrollParent(el) {
    let cur = el.parentElement;
    while (cur) {
      const { overflow, overflowY } = getComputedStyle(cur);
      if (/auto|scroll/.test(overflow + overflowY)) return cur;
      cur = cur.parentElement;
    }
    return document.documentElement;
  },

  _startAutoScroll() {
    const margin = 80;
    const speed = 0.3;
    const tick = () => {
      if (!this._drag?.active) return;
      const { y } = this._ptr;
      const sp = this._scrollParent;
      if (y < margin) {
        sp.scrollTop -= (margin - y) * speed;
      } else if (y > window.innerHeight - margin) {
        sp.scrollTop += (y - (window.innerHeight - margin)) * speed;
      }
      this._scrollRaf = requestAnimationFrame(tick);
    };
    this._scrollRaf = requestAnimationFrame(tick);
  },
};
