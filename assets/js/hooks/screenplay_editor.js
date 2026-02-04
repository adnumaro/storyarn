/**
 * ScreenplayEditor - Phoenix LiveView Hook for the fullscreen screenplay editor.
 *
 * Handles keyboard shortcuts:
 * - Escape: Close the editor
 * - Tab: Focus stage directions input
 */

export const ScreenplayEditor = {
  mounted() {
    this.handleKeyDown = this.handleKeyDown.bind(this);
    document.addEventListener("keydown", this.handleKeyDown);
  },

  handleKeyDown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.pushEvent("close_editor");
    } else if (event.key === "Tab" && !event.shiftKey) {
      const stageDirectionsInput = this.el.querySelector("#screenplay-stage-directions");
      if (stageDirectionsInput && document.activeElement !== stageDirectionsInput) {
        // Only intercept Tab if not already focused on stage directions
        const activeElement = document.activeElement;
        const isInEditor = activeElement?.closest(".ProseMirror");

        if (isInEditor) {
          event.preventDefault();
          stageDirectionsInput.focus();
          stageDirectionsInput.select();
        }
      }
    }
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeyDown);
  },
};
