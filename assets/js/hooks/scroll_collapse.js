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
        if (isScrolled) {
          this.wrapper.setAttribute("data-scrolled", "");
        } else {
          this.wrapper.removeAttribute("data-scrolled");
        }
      }
    };

    this.el.addEventListener("scroll", this.onScroll, { passive: true });
  },

  destroyed() {
    if (this.onScroll) {
      this.el.removeEventListener("scroll", this.onScroll);
    }
    if (this.wrapper) {
      this.wrapper.removeAttribute("data-scrolled");
    }
  },
};
