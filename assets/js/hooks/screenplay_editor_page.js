/**
 * ScreenplayEditorPage - Page-level orchestrator for the screenplay editor.
 *
 * Attached to the .screenplay-page container.
 * Handles focus management when new elements are created,
 * type change propagation from server auto-detect, and arrow key navigation.
 */

export const ScreenplayEditorPage = {
  mounted() {
    this.handleEvent("focus_element", ({ id }) => {
      requestAnimationFrame(() => {
        const el = document.getElementById(`sp-el-${id}`);
        if (!el) return;

        const editable = el.querySelector("[contenteditable]");
        if (!editable) return;

        editable.focus();

        // Place cursor at end
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(editable);
        range.collapse(false);
        selection.removeAllRanges();
        selection.addRange(range);
      });
    });

    this.handleEvent("element_type_changed", ({ id, type }) => {
      const wrapper = document.getElementById(`sp-el-${id}`);
      if (!wrapper) return;

      // Update CSS class using data attribute to find old type
      const oldType = wrapper.dataset.elementType;
      if (oldType) wrapper.classList.remove(`sp-${oldType}`);
      wrapper.classList.add(`sp-${type}`);
      wrapper.dataset.elementType = type;

      // Notify the ScreenplayElement hook on this element
      wrapper.dispatchEvent(new CustomEvent("typechanged", { detail: { type } }));
    });

    this.handleArrowNav = this.handleArrowNav.bind(this);
    this.el.addEventListener("keydown", this.handleArrowNav);
  },

  handleArrowNav(event) {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return;

    const active = document.activeElement;
    if (!active || !active.hasAttribute("contenteditable")) return;

    const atBoundary = this.isAtBoundary(active, event.key === "ArrowUp");
    if (!atBoundary) return;

    event.preventDefault();

    const editables = [
      ...this.el.querySelectorAll("[contenteditable=true]"),
    ];
    const index = editables.indexOf(active);
    if (index === -1) return;

    const target =
      event.key === "ArrowUp"
        ? editables[index - 1]
        : editables[index + 1];

    if (target) {
      target.focus();
      // Place cursor at start for ArrowDown, end for ArrowUp
      const sel = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(target);
      range.collapse(event.key === "ArrowDown");
      sel.removeAllRanges();
      sel.addRange(range);
    }
  },

  isAtBoundary(el, isTop) {
    const sel = window.getSelection();
    if (!sel.rangeCount) return true;

    const range = sel.getRangeAt(0);
    if (!range.collapsed) return false;

    // Single-line shortcut: if element has no block-level children or line breaks
    const hasLineBreaks = el.querySelector("br, div, p");
    if (!hasLineBreaks && el.childNodes.length <= 1) {
      return true;
    }

    // Check with range rects
    const caretRect = range.getBoundingClientRect();
    const elRect = el.getBoundingClientRect();

    // Handle zero-rect case (empty elements or collapsed ranges in some browsers)
    if (caretRect.height === 0) return true;

    if (isTop) {
      return Math.abs(caretRect.top - elRect.top) < 4;
    } else {
      return Math.abs(caretRect.bottom - elRect.bottom) < 4;
    }
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.handleArrowNav);
  },
};
