/**
 * TriStateCheckbox hook for handling checkbox with indeterminate state.
 *
 * The checkbox cycles through: true → false → null → true
 * We handle the click ourselves to prevent native checkbox behavior from interfering.
 */
export const TriStateCheckbox = {
  mounted() {
    this.syncState();

    // Handle click ourselves to control the tri-state cycle
    this.handleClick = (e) => {
      e.preventDefault();
      e.stopPropagation();

      const blockId = this.el.dataset.blockId;
      const currentState = this.el.dataset.state;

      // Cycle: true → false → null → true
      let nextValue;
      if (currentState === "true") {
        nextValue = "false";
      } else if (currentState === "false") {
        nextValue = "null";
      } else {
        nextValue = "true";
      }

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
    this.syncState();
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener("click", this.handleClick);
    }
  },

  syncState() {
    // Sync checked state
    const shouldBeChecked = this.el.dataset.state === "true";
    if (this.el.checked !== shouldBeChecked) {
      this.el.checked = shouldBeChecked;
    }

    // Sync indeterminate state
    const isIndeterminate = this.el.dataset.indeterminate === "true";
    this.el.indeterminate = isIndeterminate;
  },
};
