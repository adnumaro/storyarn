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
    if (!drop) {
      this._ind.style.display = "none";
      return;
    }
    this._ind.style.display = "block";
    this._placeIndicator(drop.el, drop.edge);
  },

  _findDrop(x, y) {
    const hit = document.elementFromPoint(x, y);
    if (!hit) return null;

    let cur = hit;
    while (cur && cur !== document.body) {
      if (
        this.el.contains(cur) &&
        (cur.classList.contains("block-wrapper") ||
          cur.classList.contains("column-group") ||
          cur.classList.contains("column-item")) &&
        cur !== this._drag.el &&
        !this._drag.el.contains(cur)
      ) {
        return { el: cur, edge: this._getEdge(cur, x, y) };
      }
      cur = cur.parentElement;
    }
    return null;
  },

  // Returns the bounding rect to use for indicator placement and edge detection.
  // For block-wrappers, the [data-id] inner element reflects the visual content
  // bounds — the wrapper itself extends into negative-margin page padding.
  _contentRect(el) {
    if (el.classList.contains("block-wrapper")) {
      const inner = el.querySelector("[data-id]");
      if (inner) return inner.getBoundingClientRect();
    }
    if (el.classList.contains("column-group")) {
      const style = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      const pl = parseFloat(style.paddingLeft);
      const pr = parseFloat(style.paddingRight);
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

    // Column items are always horizontal context
    if (el.classList.contains("column-item")) {
      return x < r.left + r.width / 2 ? "left" : "right";
    }

    // Block wrappers: left/right edges → column creation; center → vertical reorder
    // Some block types (e.g. table) do not support column layout — vertical only.
    if (el.classList.contains("block-wrapper")) {
      const inner = el.querySelector("[data-id]");
      const noColumns = inner?.dataset.blockType === "table";
      if (!noColumns) {
        const relX = (x - r.left) / r.width;
        if (relX < 0.25) return "left";
        if (relX > 0.75) return "right";
      }
      return (y - r.top) / r.height < 0.5 ? "top" : "bottom";
    }

    // Column groups: top/bottom only
    return (y - r.top) / r.height < 0.5 ? "top" : "bottom";
  },

  _placeIndicator(el, edge) {
    const r = this._contentRect(el);
    const s = this._ind.style;
    if (edge === "top") {
      s.left = `${r.left}px`;
      s.width = `${r.width}px`;
      s.top = `${r.top - 1}px`;
      s.height = "3px";
    } else if (edge === "bottom") {
      s.left = `${r.left}px`;
      s.width = `${r.width}px`;
      s.top = `${r.bottom - 1}px`;
      s.height = "3px";
    } else if (edge === "left") {
      const h = r.height * 0.8;
      s.top = `${r.top + (r.height - h) / 2}px`;
      s.height = `${h}px`;
      s.left = `${r.left - 5}px`;
      s.width = "3px";
    } else {
      const h = r.height * 0.8;
      s.top = `${r.top + (r.height - h) / 2}px`;
      s.height = `${h}px`;
      s.left = `${r.right + 3}px`;
      s.width = "3px";
    }
  },

  // ── FLIP animation ───────────────────────────────────────────────────────────

  _snapshotPositions() {
    const map = new Map();
    for (const el of this.el.querySelectorAll(
      ":scope > .block-wrapper, :scope > .column-group, .column-item"
    )) {
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
    const dragged = this._drag.el;
    const { el: target, edge } = this._drag.drop;

    const isBlock = dragged.classList.contains("block-wrapper");
    const isItem = dragged.classList.contains("column-item");
    const targetIsBlock = target.classList.contains("block-wrapper");
    const targetIsItem = target.classList.contains("column-item");

    if (edge === "left" || edge === "right") {
      if (isBlock && targetIsBlock) {
        // Two full-width blocks → merge into column
        const content = dragged.querySelector("[data-id]");
        edge === "right" ? target.appendChild(content) : target.prepend(content);
        dragged.remove();
      } else if (isItem && targetIsBlock) {
        // column-item + full-width block → create new column
        const sourceGroup = dragged.parentElement;
        edge === "right" ? target.appendChild(dragged) : target.prepend(dragged);
        // Clean up source group if it now has 0 or 1 items
        if (sourceGroup?.classList.contains("column-group")) {
          const remaining = sourceGroup.querySelectorAll("[data-id]");
          if (remaining.length === 0) {
            sourceGroup.remove();
          } else if (remaining.length === 1) {
            const promotedWrapper = document.createElement("div");
            promotedWrapper.className = "block-wrapper flex dnd-dropped";
            sourceGroup.after(promotedWrapper);
            promotedWrapper.appendChild(remaining[0]);
            sourceGroup.remove();
          }
        }
      } else if (targetIsItem) {
        // Insert into existing column group
        const content = isBlock ? dragged.querySelector("[data-id]") : dragged;
        edge === "right" ? target.after(content) : target.before(content);
        if (isBlock) dragged.remove();
      }
    } else {
      // Vertical reorder in main container
      // If target is inside a column-group, use the group as the insertion anchor
      const anchor = targetIsItem ? target.closest(".column-group") : target;
      if (isItem) {
        // Column item escaping to main container — wrap in a temporary block-wrapper
        // so it already has the correct full-width appearance before LiveView patches.
        const sourceGroup = dragged.parentElement;
        const tempWrapper = document.createElement("div");
        tempWrapper.className = "block-wrapper flex dnd-dropped";
        edge === "bottom" ? anchor.after(tempWrapper) : anchor.before(tempWrapper);
        tempWrapper.appendChild(dragged);

        // If the source column-group is left with a single item, promote it to a
        // full-width block-wrapper too so the DOM already matches what LiveView
        // will render, eliminating the visible layout flash.
        if (sourceGroup?.classList.contains("column-group")) {
          const remaining = sourceGroup.querySelectorAll("[data-id]");
          if (remaining.length === 0) {
            sourceGroup.remove();
          } else if (remaining.length === 1) {
            const promotedWrapper = document.createElement("div");
            promotedWrapper.className = "block-wrapper flex dnd-dropped";
            sourceGroup.after(promotedWrapper);
            promotedWrapper.appendChild(remaining[0]);
            sourceGroup.remove();
          }
        }
      } else {
        edge === "bottom" ? anchor.after(dragged) : anchor.before(dragged);
      }
    }

    this._animateFlip(snapshot);
    this._sendLayout();
  },

  _sendLayout() {
    const items = this._collectLayout();
    const target = this.el.dataset.phxTarget;
    if (target) {
      this.pushEventTo(target, "reorder_with_columns", { items });
    } else {
      this.pushEvent("reorder_with_columns", { items });
    }
  },

  // ── Layout collection ────────────────────────────────────────────────────────

  _collectLayout() {
    const items = [];
    for (const child of this.el.children) {
      if (child.classList.contains("column-group")) {
        const groupId = child.dataset.columnGroup;
        child.querySelectorAll("[data-id]").forEach((el, idx) => {
          items.push({ id: el.dataset.id, column_group_id: groupId, column_index: idx });
        });
      } else if (child.classList.contains("block-wrapper")) {
        const blockEls = child.querySelectorAll("[data-id]");
        if (blockEls.length === 1) {
          items.push({ id: blockEls[0].dataset.id, column_group_id: null, column_index: 0 });
        } else if (blockEls.length > 1) {
          const gid = crypto.randomUUID();
          blockEls.forEach((el, idx) => {
            items.push({ id: el.dataset.id, column_group_id: gid, column_index: idx });
          });
        }
      } else if (child.dataset.id) {
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
