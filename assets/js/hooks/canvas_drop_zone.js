/**
 * CanvasDropZone hook — shows/hides the drag overlay indicator
 * when dragging files over the map canvas.
 *
 * Uses a counter to handle nested dragenter/dragleave events
 * (child elements fire their own events).
 */
export const CanvasDropZone = {
  mounted() {
    this._counter = 0;

    this._onDragEnter = () => {
      this._counter++;
      const indicator = document.getElementById("canvas-drop-indicator");
      if (indicator) indicator.classList.remove("hidden");
    };

    this._onDragLeave = () => {
      this._counter--;
      if (this._counter === 0) {
        const indicator = document.getElementById("canvas-drop-indicator");
        if (indicator) indicator.classList.add("hidden");
      }
    };

    this._onDrop = () => {
      this._counter = 0;
      const indicator = document.getElementById("canvas-drop-indicator");
      if (indicator) indicator.classList.add("hidden");
    };

    this.el.addEventListener("dragenter", this._onDragEnter);
    this.el.addEventListener("dragleave", this._onDragLeave);
    this.el.addEventListener("drop", this._onDrop);
  },

  destroyed() {
    this.el.removeEventListener("dragenter", this._onDragEnter);
    this.el.removeEventListener("dragleave", this._onDragLeave);
    this.el.removeEventListener("drop", this._onDrop);
  },
};
