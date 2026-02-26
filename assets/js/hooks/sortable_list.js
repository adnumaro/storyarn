import Sortable from "sortablejs";
import { pushWithTarget } from "../utils/event_dispatcher";

/**
 * SortableList hook for LiveView drag-and-drop functionality.
 *
 * Usage:
 * <ul id="sortable-list" phx-hook="SortableList" data-group="fields">
 *   <li data-id="field-1" class="sortable-item">Item 1</li>
 *   <li data-id="field-2" class="sortable-item">Item 2</li>
 * </ul>
 *
 * Events:
 * - Pushes "reorder" event to LiveView with:
 *   { ids: ["field-1", "field-2", ...], group: "fields" }
 */
export const SortableList = {
  mounted() {
    const group = this.el.dataset.group || "items";
    const handle = this.el.dataset.handle || null;

    this.sortable = new Sortable(this.el, {
      animation: 150,
      handle: handle,
      draggable: "[data-id]",
      direction: "vertical",
      forceFallback: true,
      fallbackOnBody: true,
      swapThreshold: 0.65,
      invertSwap: true,
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      dragClass: "sortable-drag",
      onEnd: (_evt) => {
        const ids = Array.from(this.el.querySelectorAll("[data-id]")).map(
          (item) => item.dataset.id,
        );
        pushWithTarget(this, "reorder", { ids: ids, group: group });
      },
    });
  },

  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  },

  updated() {
    // Re-sync sortable when DOM is updated by LiveView
    // Sortable handles this automatically in most cases
  },
};

export default { SortableList };
