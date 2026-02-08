import Sortable from "sortablejs";

/**
 * ColumnSortable hook for LiveView drag-and-drop with column layout support.
 *
 * Two-tier SortableJS setup:
 * 1. Main container — sortable for full-width blocks AND column-group wrappers
 * 2. Column groups — each is a sortable container for its column items
 *
 * Column creation: drag a block to the right edge of another full-width block
 * to create a 2-column group.
 *
 * Events pushed to LiveView:
 * - "reorder_with_columns" — full layout array with column info
 * - "create_column_group" — creates a new column group from two blocks
 */
export const ColumnSortable = {
  mounted() {
    this.sortables = [];
    this.dropIndicator = null;
    this.pendingColumnTarget = null;
    this.lastMouseX = 0;
    this.initSortables();
    this.handleMouseMove = (e) => {
      this.lastMouseX = e.clientX;
    };
    document.addEventListener("mousemove", this.handleMouseMove);
  },

  updated() {
    this.destroySortables();
    this.initSortables();
  },

  destroyed() {
    this.destroySortables();
    this.removeDropIndicator();
    document.removeEventListener("mousemove", this.handleMouseMove);
  },

  initSortables() {
    const handle = this.el.dataset.handle || null;

    // Main container sortable — handles full-width items and column-group wrappers
    const mainSortable = new Sortable(this.el, {
      animation: 150,
      handle: handle,
      draggable: "[data-id], .column-group",
      direction: "vertical",
      forceFallback: true,
      fallbackOnBody: true,
      swapThreshold: 0.65,
      invertSwap: true,
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      dragClass: "sortable-drag",
      group: { name: "blocks", pull: true, put: true },
      onMove: (evt) => this.handleMainMove(evt),
      onEnd: (evt) => this.handleDrop(evt),
    });
    this.sortables.push(mainSortable);

    // Column group sortables — each column group is its own sortable
    this.el.querySelectorAll(".column-group").forEach((groupEl) => {
      const groupSortable = new Sortable(groupEl, {
        animation: 150,
        handle: handle,
        draggable: ".column-item",
        direction: "horizontal",
        forceFallback: true,
        fallbackOnBody: true,
        swapThreshold: 0.65,
        ghostClass: "sortable-ghost",
        chosenClass: "sortable-chosen",
        dragClass: "sortable-drag",
        group: {
          name: "blocks",
          pull: true,
          put: (to) => {
            // Max 3 items per column group
            const currentItems = to.el.querySelectorAll(".column-item[data-id]");
            return currentItems.length < 3;
          },
        },
        onEnd: (evt) => this.handleDrop(evt),
      });
      this.sortables.push(groupSortable);
    });
  },

  destroySortables() {
    this.sortables.forEach((s) => s.destroy());
    this.sortables = [];
  },

  handleMainMove(evt) {
    const dragged = evt.dragged;
    const related = evt.related;

    // Only show column indicator when dragging a single block near another single block
    if (!dragged.dataset.id || !related.dataset.id) {
      this.removeDropIndicator();
      this.pendingColumnTarget = null;
      return true;
    }

    // Don't allow creating columns with items already in a column group
    if (related.closest(".column-group")) {
      this.removeDropIndicator();
      this.pendingColumnTarget = null;
      return true;
    }

    // Check if cursor is in the right 30% of the related element
    const rect = related.getBoundingClientRect();
    const threshold = rect.left + rect.width * 0.7;

    if (this.lastMouseX > threshold) {
      this.showDropIndicator(related);
      this.pendingColumnTarget = related.dataset.id;
    } else {
      this.removeDropIndicator();
      this.pendingColumnTarget = null;
    }

    return true;
  },

  handleDrop(evt) {
    const draggedId = evt.item?.dataset?.id;

    // If we had a pending column creation target, create the column group
    if (this.pendingColumnTarget) {
      if (draggedId && draggedId !== this.pendingColumnTarget) {
        this.removeDropIndicator();
        const target = this.el.dataset.phxTarget;
        const payload = {
          block_ids: [this.pendingColumnTarget, draggedId],
        };
        if (target) {
          this.pushEventTo(target, "create_column_group", payload);
        } else {
          this.pushEvent("create_column_group", payload);
        }
        this.pendingColumnTarget = null;
        return;
      }
      this.pendingColumnTarget = null;
    }

    this.removeDropIndicator();

    // Collect full layout from DOM and push reorder event
    const items = this.collectLayout();
    const target = this.el.dataset.phxTarget;
    if (target) {
      this.pushEventTo(target, "reorder_with_columns", { items });
    } else {
      this.pushEvent("reorder_with_columns", { items });
    }
  },

  /**
   * Walks the container DOM and builds the layout array.
   * - Direct children with [data-id] → full-width items
   * - .column-group children → iterate their [data-id] children
   */
  collectLayout() {
    const items = [];

    for (const child of this.el.children) {
      if (child.classList.contains("column-group")) {
        const groupId = child.dataset.columnGroup;
        const columnItems = child.querySelectorAll("[data-id]");
        columnItems.forEach((item, idx) => {
          items.push({
            id: item.dataset.id,
            column_group_id: groupId,
            column_index: idx,
          });
        });
      } else if (child.dataset.id) {
        items.push({
          id: child.dataset.id,
          column_group_id: null,
          column_index: 0,
        });
      }
    }

    return items;
  },

  showDropIndicator(element) {
    this.removeDropIndicator();
    element.classList.add("column-drop-target");
    this.dropIndicator = element;
  },

  removeDropIndicator() {
    if (this.dropIndicator) {
      this.dropIndicator.classList.remove("column-drop-target");
      this.dropIndicator = null;
    }
  },
};

