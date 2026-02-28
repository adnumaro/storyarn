import {
  computePosition,
  flip,
  shift,
  offset,
  autoUpdate,
} from "@floating-ui/dom";

export const BlockMenu = {
  mounted() {
    this.reference = this.el.parentElement;
    this.cleanup = autoUpdate(this.reference, this.el, () => this.position());
  },

  updated() {
    this.position();
  },

  position() {
    computePosition(this.reference, this.el, {
      placement: "bottom-start",
      middleware: [offset(4), flip(), shift({ padding: 8 })],
    }).then(({ x, y }) => {
      Object.assign(this.el.style, { left: `${x}px`, top: `${y}px` });
    });
  },

  destroyed() {
    this.cleanup?.();
  },
};
