/**
 * SortableTree — custom pointer-event drag-and-drop for sidebar trees.
 *
 * Replaces SortableJS with a lightweight custom system:
 *  - Pointer events → works on mouse and touch
 *  - position:fixed preview of the visible row
 *  - 3-zone drop: top 30% (before), middle 40% (nest), bottom 30% (after)
 *  - Auto-scroll when cursor approaches viewport edges
 *  - Auto-expand collapsed nodes on 600ms hover
 *  - No DOM moves — LiveView patches the tree after the event
 *
 * Events pushed (unchanged from previous implementation):
 * - Sheets:  pushEvent("move_sheet", { sheet_id, parent_id, position })
 * - Others:  pushEvent("move_to_parent", { item_id, new_parent_id, position })
 */
export const SortableTree = {
  mounted() {
    this._drag = null;
    this._ptr = { x: 0, y: 0 };
    this._scrollParent = null;
    this._scrollRaf = null;
    this._preview = null;
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

    // Only drag items with cursor-grab (i.e. can_drag is true)
    const item = e.target.closest("[data-item-id]");
    if (!item || !item.classList.contains("cursor-grab")) return;
    if (!this.el.contains(item)) return;

    // Don't intercept clicks on buttons (menus, toggles, add-child)
    if (e.target.closest("button, input, .dropdown")) return;

    // Prevent native link drag (browser shows URL tooltip otherwise)
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
    this._checkAutoExpand(e.clientX, e.clientY);
  },

  _pointerUp(e) {
    if (!this._drag) return;

    if (!this._drag.active) {
      // No drag happened — simulate the click for navigation
      const link = this._drag.el.querySelector(".group\\/item a");
      if (link) link.click();
      this._cleanup();
      return;
    }

    if (this._drag.drop) this._applyDrop();
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
    this._ind.classList.remove("dnd-nest");
    this._highlightTarget?.classList.remove("dnd-drop-target");
    this._highlightTarget = null;

    if (this._scrollRaf) {
      cancelAnimationFrame(this._scrollRaf);
      this._scrollRaf = null;
    }

    this._clearExpandTimer();
    this._drag = null;
  },

  // ── Drag preview ─────────────────────────────────────────────────────────────

  _createPreview(item) {
    // Clone only the visible row (group/item), not children containers
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

  // ── Hit-testing & indicator ──────────────────────────────────────────────────

  _updateIndicator(x, y) {
    const drop = this._findDrop(x, y);
    this._drag.drop = drop;

    // Clear previous highlight
    this._highlightTarget?.classList.remove("dnd-drop-target");
    this._highlightTarget = null;

    if (!drop) {
      this._ind.style.display = "none";
      return;
    }

    if (drop.zone === "center") {
      // Highlight the item row instead of showing the indicator line
      this._ind.style.display = "none";
      const row = drop.el.querySelector(".group\\/item");
      if (row) {
        row.classList.add("dnd-drop-target");
        this._highlightTarget = row;
      }
    } else {
      this._ind.style.display = "block";
      this._placeIndicator(drop);
    }
  },

  _findDrop(x, y) {
    const hit = document.elementFromPoint(x, y);
    if (!hit) return null;

    let cur = hit;
    while (cur && cur !== document.body) {
      if (cur.dataset.itemId && this.el.contains(cur) && cur !== this._drag.el && !this._drag.el.contains(cur)) {
        return { el: cur, zone: this._getZone(cur, y) };
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
    const isLast = this._isLastSibling(item);

    if (isLast) {
      if (ratio < 0.25) return "top";
      if (ratio > 0.75) return "bottom";
      return "center";
    }

    if (ratio < 0.25) return "top";
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
    // Clamp width to the tree panel boundary
    const panel = this.el.closest("#tree-panel");
    const pb = panel ? panel.getBoundingClientRect() : null;
    const left = r.left;
    const right = pb ? Math.min(r.right, pb.right) : r.right;
    const width = right - left;
    const s = this._ind.style;

    // Only called for top/bottom zones (center uses highlight instead)
    s.top = `${drop.zone === "top" ? r.top - 1 : r.bottom - 1}px`;
    s.left = `${left}px`;
    s.width = `${width}px`;
    s.height = "3px";
  },

  _isExpanded(item) {
    const container = item.querySelector("[data-sortable-container]");
    return container && !container.classList.contains("hidden");
  },

  // ── Auto-expand collapsed nodes on hover ─────────────────────────────────────

  _checkAutoExpand(x, y) {
    const drop = this._drag?.drop;
    if (!drop || drop.zone !== "center") {
      this._clearExpandTimer();
      return;
    }

    const target = drop.el;
    // Only expand if it's a tree-node with a collapsed children container
    if (!target.classList.contains("tree-node")) {
      this._clearExpandTimer();
      return;
    }

    const content = target.querySelector("[data-sortable-container]");
    if (!content || !content.classList.contains("hidden")) {
      this._clearExpandTimer();
      return;
    }

    // Same target — timer already running
    if (this._expandTarget === target) return;

    this._clearExpandTimer();
    this._expandTarget = target;
    this._expandTimer = setTimeout(() => {
      // Simulate clicking the TreeToggle button to expand
      const toggle = target.querySelector("[phx-hook='TreeToggle']");
      if (toggle) toggle.click();
      this._expandTarget = null;
    }, 600);
  },

  _clearExpandTimer() {
    if (this._expandTimer) {
      clearTimeout(this._expandTimer);
      this._expandTimer = null;
    }
    this._expandTarget = null;
  },

  // ── Drop application ─────────────────────────────────────────────────────────

  _applyDrop() {
    const { el: dragged } = this._drag;
    const { el: target, zone } = this._drag.drop;

    const draggedId = dragged.dataset.itemId;
    const targetId = target.dataset.itemId;

    let parentId, position;

    if (zone === "center") {
      // Nest as child — parent becomes the target, position is last
      parentId = targetId;
      const container = target.querySelector("[data-sortable-container]");
      position = container
        ? Array.from(container.children).filter((el) => el.dataset.itemId && el.dataset.itemId !== draggedId).length
        : 0;
    } else {
      // Insert before/after — same parent as target
      const parentContainer = target.parentElement?.closest("[data-sortable-container]");
      parentId = parentContainer?.dataset.parentId ?? "";

      const siblings = Array.from(parentContainer?.children ?? []).filter(
        (el) => el.dataset.itemId && el.dataset.itemId !== draggedId,
      );
      const targetIndex = siblings.indexOf(target);
      position = zone === "top" ? targetIndex : targetIndex + 1;
      if (position < 0) position = 0;
    }

    if (this.treeType === "sheets") {
      this.pushEvent("move_sheet", {
        sheet_id: draggedId,
        parent_id: String(parentId),
        position: String(position),
      });
    } else {
      this.pushEvent("move_to_parent", {
        item_id: draggedId,
        new_parent_id: String(parentId),
        position: String(position),
      });
    }
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

export default { SortableTree };
