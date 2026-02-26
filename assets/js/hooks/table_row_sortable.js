import Sortable from "sortablejs";
import { pushWithTarget } from "../utils/event_dispatcher";

/**
 * TableRowSortable hook for drag-and-drop row reordering in table blocks.
 *
 * Usage:
 * <tbody id="table-rows-123" phx-hook="TableRowSortable"
 *        data-block-id="123" data-phx-target={@target}>
 *   <tr data-row-id="1">...</tr>
 *   <tr data-row-id="2">...</tr>
 * </tbody>
 *
 * Events:
 * - Pushes "reorder_table_rows" with { block_id, row_ids }
 */
export const TableRowSortable = {
  mounted() {
    this.sortable = new Sortable(this.el, {
      animation: 150,
      handle: ".row-drag-handle",
      draggable: "[data-row-id]",
      direction: "vertical",
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      onEnd: (_evt) => {
        const rowIds = Array.from(this.el.querySelectorAll("[data-row-id]")).map(
          (row) => row.dataset.rowId,
        );

        const blockId = this.el.dataset.blockId;

        pushWithTarget(this, "reorder_table_rows", {
          block_id: blockId,
          row_ids: rowIds,
        });
      },
    });
  },

  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  },
};
