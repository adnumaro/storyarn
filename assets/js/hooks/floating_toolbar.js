/**
 * FloatingToolbar hook — re-applies JS positioning after LiveView patches
 * the toolbar content (e.g. after update_pin, update_zone, etc.).
 *
 * LiveView's morphdom patching removes JS-added classes. This hook
 * re-adds the `toolbar-visible` class and re-computes position on each
 * `updated()` callback.
 */
export const FloatingToolbar = {
  updated() {
    // After LiveView patches the toolbar content, re-apply positioning.
    // The MapCanvas hook exposes its floatingToolbar on #map-canvas.__floatingToolbar
    const mapCanvas = document.getElementById("map-canvas");
    if (mapCanvas?.__floatingToolbar) {
      mapCanvas.__floatingToolbar.reposition();
    }
  },
};
