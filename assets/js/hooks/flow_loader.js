/**
 * FlowLoader — Hook that shows a GPU-composited loading overlay (in root
 * layout, outside LiveView DOM) and defers the heavy data fetch until the
 * browser has painted at least one frame.
 *
 * The overlay lives in root.html.heex so morphdom never touches it.
 * CSS animation runs on the compositor thread even when the main thread
 * is blocked by heavy DOM patching.
 */
export const FlowLoader = {
  mounted() {
    // Show root layout overlay (GPU-composited, survives LiveView DOM patching)
    document.getElementById("page-loader")?.classList.remove("hidden");

    // Guarantee at least one paint before triggering the heavy load
    requestAnimationFrame(() => {
      this.pushEvent("load_flow_data", {});
    });
  },
};
