/**
 * SceneElementPanel - Phoenix LiveView Hook for the scene element properties panel.
 *
 * Handles panel animations and close behavior, mirroring BuilderSidebar.
 * - Entry animation: slides in from the right on mount (desktop only)
 * - Exit animation: slides out to the right before server removal (desktop only)
 *
 * Close flow: close button dispatches "panel:close" DOM event → hook animates
 * out → pushEvent("close_element_panel") → server sets element_panel_open to false.
 */

const OPEN_DURATION = 280;
const CLOSE_DURATION = 180;
const ANIMATION_EASING = "ease-out";
const SLIDE_OFFSET = "20px";

export const SceneElementPanel = {
  mounted() {
    this.animateIn();

    this.el.addEventListener("panel:close", () => this.closeWithAnimation());
  },

  animateIn() {
    if (window.innerWidth < 1280) return;

    const el = this.el;

    el.style.opacity = "0";
    el.style.transform = `translateX(${SLIDE_OFFSET})`;

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        el.style.transition = `transform ${OPEN_DURATION}ms ${ANIMATION_EASING}, opacity ${OPEN_DURATION}ms ${ANIMATION_EASING}`;
        el.style.opacity = "1";
        el.style.transform = "translateX(0)";

        setTimeout(() => {
          el.style.transition = "";
          el.style.opacity = "";
          el.style.transform = "";
        }, OPEN_DURATION);
      });
    });
  },

  closeWithAnimation() {
    if (window.innerWidth < 1280) {
      this.pushEvent("close_element_panel", {});
      return;
    }

    const el = this.el;
    el.style.transition = `transform ${CLOSE_DURATION}ms ${ANIMATION_EASING}, opacity ${CLOSE_DURATION}ms ${ANIMATION_EASING}`;
    el.style.opacity = "0";
    el.style.transform = `translateX(${SLIDE_OFFSET})`;

    setTimeout(() => this.pushEvent("close_element_panel", {}), CLOSE_DURATION);
  },

  destroyed() {},
};
