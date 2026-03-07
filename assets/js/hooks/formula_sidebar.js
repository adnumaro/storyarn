/**
 * FormulaSidebar - Phoenix LiveView Hook for the formula editor right panel.
 *
 * Mirrors SceneElementPanel pattern but uses pushEventTo for LiveComponent targeting.
 * - Entry animation: slides in from the right on mount (desktop only)
 * - Exit animation: slides out to the right before server removal (desktop only)
 *
 * Close flow: close button dispatches "panel:close" DOM event → hook animates
 * out → pushEventTo("close_formula_sidebar") → server sets formula_editing to nil.
 */

const OPEN_DURATION = 280;
const CLOSE_DURATION = 180;
const ANIMATION_EASING = "ease-out";
const SLIDE_OFFSET = "20px";

export const FormulaSidebar = {
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
    const closeEvent = this.el.dataset.closeEvent || "close_formula_sidebar";
    const target = this.el.dataset.phxTarget;

    if (window.innerWidth < 1280) {
      if (target) this.pushEventTo(target, closeEvent, {});
      else this.pushEvent(closeEvent, {});
      return;
    }

    const el = this.el;
    el.style.transition = `transform ${CLOSE_DURATION}ms ${ANIMATION_EASING}, opacity ${CLOSE_DURATION}ms ${ANIMATION_EASING}`;
    el.style.opacity = "0";
    el.style.transform = `translateX(${SLIDE_OFFSET})`;

    setTimeout(() => {
      if (target) this.pushEventTo(target, closeEvent, {});
      else this.pushEvent(closeEvent, {});
    }, CLOSE_DURATION);
  },

  destroyed() {},
};
