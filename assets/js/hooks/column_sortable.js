import Sortable from "sortablejs";

/**
 * ColumnSortable hook for LiveView drag-and-drop with column layout support.
 *
 * Three-tier SortableJS setup:
 * 1. Main container — vertical sortable for block-wrappers and column-groups
 * 2. Block wrappers — horizontal sortable (put: true) so items can drop next
 *    to existing blocks, creating column groups via native SortableJS ghost
 * 3. Column groups — horizontal sortable for existing column items
 *
 * ALL drops go through the same flow: collectLayout() → reorder_with_columns.
 * If a block-wrapper ends up with 2+ blocks, collectLayout generates a UUID
 * and treats them as a new column group. No special create_column_group event.
 */
export const ColumnSortable = {
  mounted() {
    this.sortables = [];
    this.initSortables();
  },

  updated() {
    this.destroySortables();
    this.initSortables();
  },

  destroyed() {
    this.destroySortables();
  },

  initSortables() {
    const handle = this.el.dataset.handle || null;

    // Main container — vertical sortable for block-wrappers and column-groups
    const mainSortable = new Sortable(this.el, {
      animation: 150,
      handle: handle,
      draggable: ".block-wrapper, .column-group",
      direction: "vertical",
      forceFallback: true,
      fallbackOnBody: true,
      swapThreshold: 0.65,
      invertSwap: true,
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      dragClass: "sortable-drag",
      group: { name: "blocks", pull: true, put: true },
      onClone: (evt) => {
        evt.clone.removeAttribute("id");
        for (const el of evt.clone.querySelectorAll("[id]")) el.removeAttribute("id");
      },
      onEnd: (evt) => {
        this.handleDrop(evt);
      },
    });
    this.sortables.push(mainSortable);

    // Block wrappers — horizontal drop targets for column creation.
    // put() uses cursor X position: only accept drops near left/right edges
    // (< 30% or > 70% of wrapper width) to avoid competing with vertical sort.
    this.el.querySelectorAll(".block-wrapper").forEach((wrapperEl) => {
      const wrapperSortable = new Sortable(wrapperEl, {
        animation: 150,
        direction: "horizontal",
        sort: false,
        handle: ".no-drag-from-wrapper",
        ghostClass: "sortable-ghost",
        group: {
          name: "blocks",
          put: (_to, _from, _dragEl, evt) => {
            if (!evt) return false;
            const rect = wrapperEl.getBoundingClientRect();
            const relX = (evt.clientX - rect.left) / rect.width;
            return relX < 0.3 || relX > 0.7;
          },
          pull: false,
        },
        onAdd: (evt) => {
          this.handleDrop(evt);
        },
      });
      this.sortables.push(wrapperSortable);
    });

    // Column groups — horizontal sortable for existing column items
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
            const currentItems = to.el.querySelectorAll(".column-item[data-id]");
            return currentItems.length < 3;
          },
        },
        onClone: (evt) => {
          evt.clone.removeAttribute("id");
          for (const el of evt.clone.querySelectorAll("[id]")) el.removeAttribute("id");
        },
        onEnd: (evt) => {
          this.handleDrop(evt);
        },
      });
      this.sortables.push(groupSortable);
    });
  },

  destroySortables() {
    this.sortables.forEach((s) => {
      s.destroy();
    });
    this.sortables = [];
  },

  handleDrop() {
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
   * - .column-group → existing column group, read children
   * - .block-wrapper with 1 [data-id] → full-width item
   * - .block-wrapper with 2+ [data-id] → new column group (generate UUID)
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
      } else if (child.classList.contains("block-wrapper")) {
        const blockEls = child.querySelectorAll("[data-id]");

        if (blockEls.length === 1) {
          // Single block — full-width
          items.push({
            id: blockEls[0].dataset.id,
            column_group_id: null,
            column_index: 0,
          });
        } else if (blockEls.length > 1) {
          // Multiple blocks dropped together — new column group
          const newGroupId = crypto.randomUUID();
          blockEls.forEach((el, idx) => {
            items.push({
              id: el.dataset.id,
              column_group_id: newGroupId,
              column_index: idx,
            });
          });
        }
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
};
