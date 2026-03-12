/**
 * RightSidebar - Unified hook for right-side sliding panels.
 *
 * Always in the DOM. Hidden by default via CSS rule:
 *   [phx-hook="RightSidebar"]:not([data-panel-open]) { display: none }
 *
 * The hook controls visibility by adding/removing the `data-panel-open`
 * attribute — which is NOT in any template, so LiveView patches can't
 * overwrite it.
 *
 * Opened by:
 *   - "panel:toggle" DOM event (any trigger button, client-side)
 *   - "panel:open"  DOM event (server push_event → global listener in app.js)
 * Closed by:
 *   - "panel:close" DOM event (close button, outside click, Escape, or
 *     another panel's data-close-panels)
 *
 * The hook pushes server events on open/close so the server can load content
 * lazily and track panel state.
 *
 * Data attributes (on the sidebar element):
 *   data-open-event    — server event pushed on open (optional)
 *   data-close-event   — server event pushed on close
 *   data-phx-target    — CSS selector for pushEventTo (optional)
 *   data-close-panels  — space-separated IDs of panels to close when this
 *                         panel opens (mutual exclusion)
 *
 * Trigger buttons use:
 *   data-panel-trigger="<panel-id>"  — hook finds this to toggle active class
 */

const OPEN_MS = 280;
const CLOSE_MS = 180;
const EASING = "ease-out";
const OFFSET = "20px";

export const RightSidebar = {
  mounted() {
    this._open = false;
    this._animating = false;

    // Find dock/trigger button that controls this panel
    this._trigger = document.querySelector(`[data-panel-trigger="${this.el.id}"]`);

    // CSS hides us by default (no data-panel-open attr) — nothing to do here.

    this.el.addEventListener("panel:open", () => this._doOpen());
    this.el.addEventListener("panel:toggle", () => this._toggle());
    this.el.addEventListener("panel:close", () => this._doClose());

    // Outside click (desktop)
    this._onPointerDown = (e) => {
      if (!this._open || this._animating) return;
      if (window.innerWidth < 1280) return;
      if (this.el.contains(e.target)) return;
      if (e.target.closest("[role='dialog']") || e.target.closest(".modal")) return;
      if (e.target.closest(".dock-item")) return;
      if (e.target.closest("[data-panel-trigger]")) return;
      this._doClose();
    };
    requestAnimationFrame(() => {
      document.addEventListener("pointerdown", this._onPointerDown);
    });

    // Escape
    this._onKeyDown = (e) => {
      if (this._open && !this._animating && e.key === "Escape") {
        e.preventDefault();
        this._doClose();
      }
    };
    document.addEventListener("keydown", this._onKeyDown);
  },

  // Re-apply visibility after LiveView patches (morphdom strips our attribute)
  updated() {
    if (this._open && !this.el.hasAttribute("data-panel-open")) {
      this.el.setAttribute("data-panel-open", "");
    }
  },

  _toggle() {
    if (this._animating) return;
    if (this._open) this._doClose();
    else this._doOpen();
  },

  _doOpen() {
    if (this._open) return;
    this._open = true;

    // Close ALL other right-side panels (universal mutual exclusion)
    document.querySelectorAll(`[data-right-panel]:not(#${this.el.id})`).forEach((el) => {
      el.dispatchEvent(new Event("panel:close"));
    });

    this.el.setAttribute("data-panel-open", "");
    if (this._trigger) this._trigger.classList.add("dock-btn-active");

    const evt = this.el.dataset.openEvent;
    if (evt) {
      const target = this.el.dataset.phxTarget;
      if (target) this.pushEventTo(target, evt, {});
      else this.pushEvent(evt, {});
    }

    if (window.innerWidth >= 1280) {
      this._animate(
        [
          { opacity: 0, transform: `translateX(${OFFSET})` },
          { opacity: 1, transform: "translateX(0)" },
        ],
        OPEN_MS,
      );
    }
  },

  _doClose() {
    if (!this._open) return;

    const finish = () => {
      this.el.removeAttribute("data-panel-open");
      this._open = false;
      if (this._trigger) this._trigger.classList.remove("dock-btn-active");

      const evt = this.el.dataset.closeEvent;
      const target = this.el.dataset.phxTarget;
      if (evt) {
        if (target) this.pushEventTo(target, evt, {});
        else this.pushEvent(evt, {});
      }
    };

    if (window.innerWidth < 1280) {
      finish();
      return;
    }

    this._animate(
      [
        { opacity: 1, transform: "translateX(0)" },
        { opacity: 0, transform: `translateX(${OFFSET})` },
      ],
      CLOSE_MS,
      finish,
    );
  },

  _animate(keyframes, duration, onDone) {
    this._animating = true;

    if (this._anim) {
      this._anim.cancel();
      this._anim = null;
    }

    const done = () => {
      clearTimeout(timer);
      this._animating = false;
      this._anim = null;
      if (onDone) onDone();
    };

    const timer = setTimeout(done, duration + 50);

    const anim = this.el.animate(keyframes, {
      duration,
      easing: EASING,
      fill: "forwards",
    });
    this._anim = anim;

    anim.onfinish = done;
    anim.oncancel = () => {
      clearTimeout(timer);
      this._animating = false;
      this._anim = null;
    };
  },

  destroyed() {
    if (this._anim) this._anim.cancel();
    document.removeEventListener("pointerdown", this._onPointerDown);
    document.removeEventListener("keydown", this._onKeyDown);
  },
};
