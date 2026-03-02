/**
 * CanvasToolbar — unified Phoenix LiveView Hook for canvas floating toolbars.
 *
 * Repositions the floating toolbar after LiveView patches update its content.
 * Works with both flow (Rete) and scene (Leaflet) canvases via data-canvas-id.
 *
 * Usage: <div phx-hook="CanvasToolbar" data-canvas-id="flow-canvas">
 */
export const CanvasToolbar = {
  updated() {
    const canvasId = this.el.dataset.canvasId;
    if (!canvasId) return;

    const canvas = document.getElementById(canvasId);
    if (canvas?.__floatingToolbar) {
      canvas.__floatingToolbar.reposition();
    }
  },
};
