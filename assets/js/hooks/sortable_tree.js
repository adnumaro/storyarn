import Sortable from "sortablejs";

/**
 * SortableTree hook for nested drag-and-drop in page trees.
 *
 * Usage:
 * <div id="pages-tree" phx-hook="SortableTree">
 *   <div data-sortable-container data-parent-id="">
 *     <div data-page-id="1" class="tree-node">
 *       Page 1
 *       <div data-sortable-container data-parent-id="1">
 *         <div data-page-id="2" class="tree-node">Child</div>
 *       </div>
 *     </div>
 *   </div>
 * </div>
 *
 * Events:
 * - Pushes "move_page" event to LiveView with:
 *   { page_id: "1", parent_id: "2" | null, position: 0 }
 */
export const SortableTree = {
  mounted() {
    this.sortables = [];
    this.initializeSortables();
  },

  updated() {
    // Reinitialize sortables when DOM is updated
    this.destroySortables();
    this.initializeSortables();
  },

  destroyed() {
    this.destroySortables();
  },

  initializeSortables() {
    const containers = this.el.querySelectorAll("[data-sortable-container]");

    for (const container of containers) {
      const sortable = new Sortable(container, {
        group: "pages-tree",
        animation: 150,
        fallbackOnBody: true,
        swapThreshold: 0.65,
        draggable: "[data-page-id]", // Only elements with data-page-id are draggable
        ghostClass: "sortable-ghost",
        chosenClass: "sortable-chosen",
        dragClass: "sortable-drag",
        delay: 150, // Small delay to distinguish click from drag
        delayOnTouchOnly: true,

        onEnd: (event) => {
          // Ignore if no actual move happened
          if (event.from === event.to && event.oldIndex === event.newIndex) {
            return;
          }

          const pageId = event.item.dataset.pageId;
          const newParentId = event.to.dataset.parentId || null;

          // Calculate position based on sibling elements with data-page-id
          const siblings = Array.from(event.to.children).filter((el) => el.dataset.pageId);
          const newPosition = siblings.indexOf(event.item);

          this.pushEvent("move_page", {
            page_id: pageId,
            parent_id: newParentId,
            position: newPosition >= 0 ? newPosition : 0,
          });
        },
      });

      this.sortables.push(sortable);
    }
  },

  destroySortables() {
    for (const sortable of this.sortables) {
      if (sortable) {
        sortable.destroy();
      }
    }
    this.sortables = [];
  },
};

export default { SortableTree };
