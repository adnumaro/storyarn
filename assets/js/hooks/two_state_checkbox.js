/**
 * TwoStateCheckbox hook for handling simple boolean checkbox.
 *
 * Toggles between true and false.
 * We handle the click ourselves to prevent native checkbox behavior from interfering.
 */
export const TwoStateCheckbox = {
  mounted() {
    // Sync checked state from data attribute
    this.syncCheckedState();

    this.handleClick = (e) => {
      e.preventDefault();
      e.stopPropagation();

      const blockId = this.el.dataset.blockId;
      const currentState = this.el.dataset.state;

      // Toggle: true → false, false → true
      const nextValue = currentState === "true" ? "false" : "true";

      const target = this.el.dataset.phxTarget;
      if (target) {
        this.pushEventTo(target, "set_boolean_block", { id: blockId, value: nextValue });
      } else {
        this.pushEvent("set_boolean_block", { id: blockId, value: nextValue });
      }
    };

    this.el.addEventListener("click", this.handleClick);
  },

  updated() {
    // Re-sync checked state after LiveView patches the DOM
    this.syncCheckedState();
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener("click", this.handleClick);
    }
  },

  syncCheckedState() {
    // Ensure the visual checked state matches the data-state attribute
    const shouldBeChecked = this.el.dataset.state === "true";
    if (this.el.checked !== shouldBeChecked) {
      this.el.checked = shouldBeChecked;
    }
  },
};
