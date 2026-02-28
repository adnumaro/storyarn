/**
 * ScrollCollapse hook — toggles `data-scrolled` on `#layout-wrapper`
 * when the <main> element scrolls past a threshold.
 *
 * CSS transitions on `.toolbar-collapsible` handle the animation.
 */
export const ScrollCollapse = {
  mounted() {
    this.wrapper = document.getElementById("layout-wrapper");
    if (!this.wrapper) return;

    this.scrolled = false;

    this.onScroll = () => {
      const isScrolled = this.el.scrollTop > 48;
      if (isScrolled !== this.scrolled) {
        this.scrolled = isScrolled;
        this._applyState();
      }
    };

    this.el.addEventListener("scroll", this.onScroll, { passive: true });
  },

  updated() {
    if (!this.scrolled) return;
    // Suppress transitions during patch to prevent flash
    const els = document.querySelectorAll(".toolbar-collapsible");
    for (const el of els) el.style.transition = "none";
    this._applyState();
    requestAnimationFrame(() => {
      for (const el of els) el.style.transition = "";
    });
  },

  destroyed() {
    if (this.onScroll) {
      this.el.removeEventListener("scroll", this.onScroll);
    }
    if (this.wrapper) {
      this.wrapper.removeAttribute("data-scrolled");
    }
  },

  _applyState() {
    if (!this.wrapper) return;
    if (this.scrolled) {
      this.wrapper.setAttribute("data-scrolled", "");
    } else {
      this.wrapper.removeAttribute("data-scrolled");
    }
  },
};
