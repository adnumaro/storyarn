/**
 * ScreenplayElement - Phoenix LiveView Hook for individual screenplay elements.
 *
 * Handles contenteditable input with debounced saves to the server.
 * Manages the sp-empty CSS class for placeholder display.
 */

const DEBOUNCE_MS = 500;

// Hint sent with create_next_element — the server computes the authoritative
// next type from the element's current (possibly auto-detected) type.
const NEXT_TYPE = {
  scene_heading: "action",
  action: "action",
  character: "dialogue",
  parenthetical: "dialogue",
  dialogue: "action",
  transition: "scene_heading",
};

const TYPE_CYCLE = [
  "action",
  "scene_heading",
  "character",
  "dialogue",
  "parenthetical",
  "transition",
];

export const ScreenplayElement = {
  mounted() {
    this.elementId = this.el.dataset.elementId;
    this.elementType = this.el.dataset.elementType;
    this.debounceTimer = null;

    // Find the editable block inside the wrapper
    this.editableBlock = this.el.querySelector("[contenteditable]");
    if (!this.editableBlock) return;

    this.handleInput = this.handleInput.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.handleTypeChanged = this.handleTypeChanged.bind(this);
    this.editableBlock.addEventListener("input", this.handleInput);
    this.editableBlock.addEventListener("keydown", this.handleKeyDown);
    this.el.addEventListener("typechanged", this.handleTypeChanged);

    this.updatePlaceholder();
  },

  handleInput() {
    this.updatePlaceholder();

    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      const content = this.editableBlock.textContent;
      this.pushEvent("update_element_content", {
        id: this.elementId,
        content: content,
      });
    }, DEBOUNCE_MS);
  },

  handleKeyDown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      this.flushDebounce();

      const nextType = NEXT_TYPE[this.elementType] || "action";
      this.pushEvent("create_next_element", {
        after_id: this.elementId,
        type: nextType,
        content: "",
      });
    } else if (event.key === "Backspace") {
      const content = this.editableBlock.textContent;
      if (content === "") {
        event.preventDefault();
        this.pushEvent("delete_element", { id: this.elementId });
      }
    } else if (event.key === "Tab") {
      event.preventDefault();
      const currentIndex = TYPE_CYCLE.indexOf(this.elementType);
      if (currentIndex === -1) return;

      const direction = event.shiftKey ? -1 : 1;
      const nextIndex =
        (currentIndex + direction + TYPE_CYCLE.length) % TYPE_CYCLE.length;
      const newType = TYPE_CYCLE[nextIndex];

      this.updateElementType(newType);
      this.pushEvent("change_element_type", {
        id: this.elementId,
        type: newType,
      });
    }
  },

  /**
   * Handles server-initiated type changes (from auto-detect).
   * Dispatched as a custom DOM event from ScreenplayEditorPage hook.
   */
  handleTypeChanged(event) {
    this.elementType = event.detail.type;
  },

  /**
   * Updates the DOM class and data attributes when type changes locally (Tab cycling).
   */
  updateElementType(newType) {
    const oldType = this.elementType;
    this.el.classList.remove(`sp-${oldType}`);
    this.el.classList.add(`sp-${newType}`);
    this.el.dataset.elementType = newType;
    this.elementType = newType;
  },

  flushDebounce() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
      const content = this.editableBlock.textContent;
      this.pushEvent("update_element_content", {
        id: this.elementId,
        content: content,
      });
    }
  },

  updatePlaceholder() {
    const isEmpty = !this.editableBlock.textContent.trim();
    this.el.classList.toggle("sp-empty", isEmpty);
  },

  destroyed() {
    clearTimeout(this.debounceTimer);
    if (this.editableBlock) {
      this.editableBlock.removeEventListener("input", this.handleInput);
      this.editableBlock.removeEventListener("keydown", this.handleKeyDown);
    }
    this.el.removeEventListener("typechanged", this.handleTypeChanged);
  },
};
