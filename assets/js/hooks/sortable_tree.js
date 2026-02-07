import Sortable from "sortablejs";

/**
 * SortableTree hook for nested drag-and-drop in sheet/flow trees.
 *
 * Usage:
 * <div id="sheets-tree" phx-hook="SortableTree">
 *   <div data-sortable-container data-parent-id="">
 *     <div data-sheet-id="1" class="tree-node">
 *       Sheet 1
 *       <div data-sortable-container data-parent-id="1">
 *         <div data-sheet-id="2" class="tree-node">Child</div>
 *       </div>
 *     </div>
 *   </div>
 * </div>
 *
 * For flows, add data-tree-type="flows" to the container:
 * <div id="flows-tree" phx-hook="SortableTree" data-tree-type="flows">
 *   ...
 * </div>
 *
 * Events:
 * - For sheets: Pushes "move_sheet" event with { sheet_id, parent_id, position }
 * - For flows: Pushes "move_to_parent" event with { item_id, new_parent_id, position }
 */
export const SortableTree = {
  mounted() {
    this.sortables = [];
    this.treeType = this.el.dataset.treeType || "sheets";
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
    const groupName = this.treeType === "flows" ? "flows-tree" : "sheets-tree";

    for (const container of containers) {
      const sortable = new Sortable(container, {
        group: groupName,
        animation: 150,
        fallbackOnBody: true,
        swapThreshold: 0.65,
        draggable: "[data-sheet-id]", // Uses data-sheet-id for both sheets and flows
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

          const itemId = event.item.dataset.sheetId;
          const newParentId = event.to.dataset.parentId || null;

          // Calculate position based on sibling elements with data-sheet-id
          const siblings = Array.from(event.to.children).filter((el) => el.dataset.sheetId);
          const newPosition = siblings.indexOf(event.item);

          if (this.treeType === "flows") {
            this.pushEvent("move_to_parent", {
              item_id: itemId,
              new_parent_id: newParentId,
              position: String(newPosition >= 0 ? newPosition : 0),
            });
          } else {
            this.pushEvent("move_sheet", {
              sheet_id: itemId,
              parent_id: newParentId,
              position: newPosition >= 0 ? newPosition : 0,
            });
          }
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
