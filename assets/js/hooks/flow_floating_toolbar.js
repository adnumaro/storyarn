/**
 * FlowFloatingToolbar — Phoenix LiveView Hook.
 *
 * Repositions the floating toolbar after LiveView patches update its content.
 * The toolbar element is rendered server-side and positioned by
 * flow_canvas/floating_toolbar.js.
 */
export const FlowFloatingToolbar = {
  updated() {
    // After LiveView patches toolbar content, reposition it above the node
    const canvas = this.el.parentElement?.querySelector("#flow-canvas");
    if (canvas?.parentElement?.__floatingToolbar) {
      canvas.parentElement.__floatingToolbar.reposition();
    }
  },
};
