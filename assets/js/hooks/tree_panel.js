/**
 * TreePanel hook — manages tree panel pin state and open/close animation.
 *
 * Animation mirrors BuilderSidebar (right panel) but slides from the left:
 * - Entry: translateX(-20px) → translateX(0), opacity 0→1, 280ms ease-out
 * - Exit:  translateX(0) → translateX(-20px), opacity 1→0, 180ms ease-out
 *
 * Pin state is stored per-tool in localStorage:
 *   storyarn:tree_panel:pinned:{tool} = "true" | "false"
 *
 * Defaults: sheets/screenplays = pinned, flows/scenes = unpinned.
 */

const OPEN_DURATION = 280;
const CLOSE_DURATION = 180;
const EASING = "ease-out";
const SLIDE_OFFSET = "-20px";
const KEY_PREFIX = "storyarn:tree_panel:pinned:";
const OLD_KEY = "storyarn:tree_panel:pinned";

const DEFAULTS = {
  sheets: true,
  screenplays: true,
  flows: false,
  scenes: false,
};

function storageKey(tool) {
  return `${KEY_PREFIX}${tool}`;
}

function readPinned(tool) {
  const stored = localStorage.getItem(storageKey(tool));
  if (stored !== null) return stored === "true";
  return DEFAULTS[tool] ?? true;
}

export const TreePanel = {
  mounted() {
    // Migrate: remove old shared key
    localStorage.removeItem(OLD_KEY);

    const tool = this.el.dataset.tool || "sheets";
    this._tool = tool;

    const pinned = readPinned(tool);

    const serverOpen = this.el.dataset.open === "true";

    if (pinned || serverOpen) {
      // Show immediately — either localStorage says pinned, or server rendered open
      // (e.g., index pages). Override the server-rendered `opacity-0` class with an
      // inline style so the panel is visible while the tree_panel_init roundtrip completes.
      this.el.style.opacity = "1";
      this.el.style.pointerEvents = "auto";
      this._open = true;
      this._pendingInit = true;
    } else {
      this._open = false;
      this.el.style.transform = `translateX(${SLIDE_OFFSET})`;
    }

    this.pushEvent("tree_panel_init", { pinned });
  },

  updated() {
    const pinned = this.el.dataset.pinned === "true";
    const tool = this.el.dataset.tool || this._tool || "sheets";
    this._tool = tool;

    const nowOpen = this.el.dataset.open === "true";

    if (this._pendingInit) {
      if (nowOpen) {
        // Server confirmed open — now data-pinned reflects the real state.
        // Persist it only now, not during the pending phase where data-pinned
        // is still the server default (false) and would corrupt localStorage.
        localStorage.setItem(storageKey(tool), String(pinned));
        this._pendingInit = false;
        this.el.style.opacity = "";
        this.el.style.pointerEvents = "";
        this._open = true;
      }
      // Keep the inline style override active until the server confirms.
      return;
    }

    // Normal operation: persist pin state and animate on state change.
    localStorage.setItem(storageKey(tool), String(pinned));

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
