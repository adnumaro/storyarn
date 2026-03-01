/**
 * BuilderSidebar - Phoenix LiveView Hook for the condition/instruction builder panel.
 *
 * Handles panel animations and close behavior, mirroring DialogueScreenplayEditor.
 * - Entry animation: slides in from the right on mount (desktop only)
 * - Exit animation: slides out to the right before server removal (desktop only)
 *
 * Close flow: close button dispatches "panel:close" DOM event → hook animates
 * out → pushEvent("close_builder") to server → server sets editing_mode back to :toolbar.
 */

const OPEN_DURATION = 280;
const CLOSE_DURATION = 180;
const ANIMATION_EASING = "ease-out";
// Small lateral drift — panel appears near its final position, not from offscreen
const SLIDE_OFFSET = "20px";

export const BuilderSidebar = {
  mounted() {
    // Entry animation (desktop only — mobile is fullscreen, no slide)
    this.animateIn();

    // Intercept close requests to animate out first.
    // "panel:close" → pushes "close_builder" (back to toolbar mode, node stays selected)
    this.el.addEventListener("panel:close", () => this.closeWithAnimation());
  },

  animateIn() {
    if (window.innerWidth < 1280) return;

    const el = this.el;

    // Set initial hidden state synchronously so the browser paints it before animating
    el.style.opacity = "0";
    el.style.transform = `translateX(${SLIDE_OFFSET})`;

    // Double rAF: first ensures the hidden state is painted, second triggers the transition
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        el.style.transition = `transform ${OPEN_DURATION}ms ${ANIMATION_EASING}, opacity ${OPEN_DURATION}ms ${ANIMATION_EASING}`;
        el.style.opacity = "1";
        el.style.transform = "translateX(0)";

        // Clean up inline styles after animation so CSS takes over
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
      this.pushEvent("close_builder", {});
      return;
    }

    const el = this.el;
    el.style.transition = `transform ${CLOSE_DURATION}ms ${ANIMATION_EASING}, opacity ${CLOSE_DURATION}ms ${ANIMATION_EASING}`;
    el.style.opacity = "0";
    el.style.transform = `translateX(${SLIDE_OFFSET})`;

    // Element stays hidden (inline styles remain) until the server removes it from DOM
    setTimeout(() => this.pushEvent("close_builder", {}), CLOSE_DURATION);
  },

  destroyed() {},
};
