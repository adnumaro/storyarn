/**
 * TableCellCheckbox hook for handling boolean cells in table blocks.
 *
 * Same pattern as TwoStateCheckbox but pushes toggle_table_cell_boolean
 * with row-id and column-slug instead of block-id.
 */
export const TableCellCheckbox = {
  mounted() {
    this.syncCheckedState();

    this.handleClick = (e) => {
      e.preventDefault();
      e.stopPropagation();

      const rowId = this.el.dataset.rowId;
      const columnSlug = this.el.dataset.columnSlug;

      const target = this.el.dataset.phxTarget;
      if (target) {
        this.pushEventTo(target, "toggle_table_cell_boolean", {
          "row-id": rowId,
          "column-slug": columnSlug,
        });
      } else {
        this.pushEvent("toggle_table_cell_boolean", {
          "row-id": rowId,
          "column-slug": columnSlug,
        });
      }
    };

    this.el.addEventListener("click", this.handleClick);
  },

  updated() {
    this.syncCheckedState();
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener("click", this.handleClick);
    }
  },

  syncCheckedState() {
    const shouldBeChecked = this.el.dataset.state === "true";
    if (this.el.checked !== shouldBeChecked) {
      this.el.checked = shouldBeChecked;
    }
  },
};
