/**
 * TreePanel hook — manages tree panel pin state and open/close animation.
 *
 * Animation mirrors BuilderSidebar (right panel) but slides from the left:
 * - Entry: translateX(-20px) → translateX(0), opacity 0→1, 280ms ease-out
 * - Exit:  translateX(0) → translateX(-20px), opacity 1→0, 180ms ease-out
 *
 * The server controls open state via data-open and CSS opacity-0/pointer-events-none.
 * JS overrides inline styles during animation (inline > class specificity), then
 * clears them so CSS classes take over when the animation ends.
 */

const OPEN_DURATION = 280;
const CLOSE_DURATION = 180;
const EASING = "ease-out";
const SLIDE_OFFSET = "-20px";
const STORAGE_KEY = "storyarn:tree_panel:pinned";

export const TreePanel = {
  mounted() {
    const stored = localStorage.getItem(STORAGE_KEY);
    const pinned = stored === null ? true : stored === "true";
    this.pushEvent("tree_panel_init", { pinned });

    this._open = this.el.dataset.open === "true";

    // Set initial transform for closed state (no animation on first render)
    if (!this._open) {
      this.el.style.transform = `translateX(${SLIDE_OFFSET})`;
    }
  },

  updated() {
    // Persist pin state on every update
    const pinned = this.el.dataset.pinned === "true";
    localStorage.setItem(STORAGE_KEY, String(pinned));

    // Animate on open/close state change
    const nowOpen = this.el.dataset.open === "true";
    if (nowOpen !== this._open) {
      this._open = nowOpen;
      nowOpen ? this._animateIn() : this._animateOut();
    }
  },

  _animateIn() {
    if (window.innerWidth < 1280) return;

    const el = this.el;
    // LiveView just removed opacity-0 class — set starting position for animation
    el.style.opacity = "0";
    el.style.transform = `translateX(${SLIDE_OFFSET})`;
    el.style.transition = "";

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        el.style.transition = `transform ${OPEN_DURATION}ms ${EASING}, opacity ${OPEN_DURATION}ms ${EASING}`;
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

  _animateOut() {
    if (window.innerWidth < 1280) return;

    const el = this.el;
    // Override CSS opacity-0 class during animation so it doesn't snap immediately
    el.style.opacity = "1";
    el.style.transform = "translateX(0)";

    requestAnimationFrame(() => {
      el.style.transition = `transform ${CLOSE_DURATION}ms ${EASING}, opacity ${CLOSE_DURATION}ms ${EASING}`;
      el.style.opacity = "0";
      el.style.transform = `translateX(${SLIDE_OFFSET})`;

      // After animation: clear transition, keep offset transform for next open
      setTimeout(() => {
        el.style.transition = "";
        el.style.opacity = "";
        el.style.transform = `translateX(${SLIDE_OFFSET})`;
      }, CLOSE_DURATION);
    });
  },

  destroyed() {},
};
