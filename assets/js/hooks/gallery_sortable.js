import { pushWithTarget } from "../utils/event_dispatcher";

/**
 * GallerySortable hook for drag-to-reorder gallery thumbnails.
 * Uses HTML5 drag API for lightweight reordering.
 */
export const GallerySortable = {
  mounted() {
    this._setupSortable();
  },

  updated() {
    this._setupSortable();
  },

  _setupSortable() {
    const container = this.el;
    let dragItem = null;

    // Clean up previous listeners
    if (this._cleanup) this._cleanup();

    const items = container.querySelectorAll("[data-id]");

    const onDragStart = (e) => {
      dragItem = e.currentTarget;
      dragItem.classList.add("opacity-30");
      e.dataTransfer.effectAllowed = "move";
    };

    const onDragEnd = (e) => {
      e.currentTarget.classList.remove("opacity-30");
      dragItem = null;
    };

    const onDragOver = (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";

      const target = e.currentTarget;
      if (!dragItem || target === dragItem) return;

      const rect = target.getBoundingClientRect();
      const midX = rect.left + rect.width / 2;

      if (e.clientX < midX) {
        container.insertBefore(dragItem, target);
      } else {
        container.insertBefore(dragItem, target.nextSibling);
      }
    };

    const onDrop = (e) => {
      e.preventDefault();
      const orderedIds = Array.from(container.querySelectorAll("[data-id]")).map(
        (el) => el.dataset.id,
      );

      pushWithTarget(this, "reorder_gallery_images", {
        block_id: container.dataset.blockId,
        ids: orderedIds,
      });
    };

    items.forEach((item) => {
      item.draggable = true;
      item.addEventListener("dragstart", onDragStart);
      item.addEventListener("dragend", onDragEnd);
      item.addEventListener("dragover", onDragOver);
      item.addEventListener("drop", onDrop);
    });

    this._cleanup = () => {
      items.forEach((item) => {
        item.removeEventListener("dragstart", onDragStart);
        item.removeEventListener("dragend", onDragEnd);
        item.removeEventListener("dragover", onDragOver);
        item.removeEventListener("drop", onDrop);
      });
    };
  },

  destroyed() {
    if (this._cleanup) this._cleanup();
  },
};
