/**
 * Shared floating popover utility using @floating-ui/dom.
 *
 * Creates a popover element appended to `document.body` (escapes any
 * overflow:hidden/clip ancestor) and keeps it positioned relative to a
 * trigger element via `autoUpdate` (handles scroll, resize, layout shifts).
 *
 * Usage:
 *   import { createFloatingPopover } from "../utils/floating_popover";
 *
 *   // In mounted():
 *   this.fp = createFloatingPopover(triggerEl, {
 *     class: "my-popover",          // CSS class(es) on the container
 *     width: "14rem",               // optional fixed width
 *     placement: "bottom-start",    // floating-ui placement
 *     offset: 4,                    // gap in px
 *     onClose: () => { ... },       // called on outside click / Escape
 *   });
 *
 *   // Populate it (the container is a plain DOM element):
 *   this.fp.el.innerHTML = "...";
 *   // or append children:
 *   this.fp.el.appendChild(myChild);
 *
 *   // Show / hide:
 *   this.fp.open();
 *   this.fp.close();
 *   this.fp.isOpen;   // boolean
 *
 *   // In destroyed():
 *   this.fp.destroy();
 */
import { autoUpdate, computePosition, flip, offset as offsetMw, shift } from "@floating-ui/dom";

/**
 * @param {HTMLElement} trigger
 * @param {Object} opts
 * @returns {{ el: HTMLDivElement, open: Function, close: Function, destroy: Function, isOpen: boolean }}
 */
export function createFloatingPopover(trigger, opts = {}) {
  const {
    class: className = "",
    width = "",
    placement = "bottom-start",
    offset = 4,
    onClose,
  } = opts;

  // Create container appended to body
  const el = document.createElement("div");
  el.style.cssText = `position:fixed;z-index:9999;display:none;`;
  if (width) el.style.width = width;
  if (className) el.className = className;
  document.body.appendChild(el);

  let cleanupAutoUpdate = null;
  let outsideClickHandler = null;
  let escapeHandler = null;
  let isOpen = false;

  function reposition() {
    computePosition(trigger, el, {
      placement,
      strategy: "fixed",
      middleware: [offsetMw(offset), flip(), shift({ padding: 8 })],
    }).then(({ x, y }) => {
      Object.assign(el.style, { left: `${x}px`, top: `${y}px` });
    });
  }

  function open() {
    if (isOpen) return;
    isOpen = true;
    el.style.display = "block";

    cleanupAutoUpdate = autoUpdate(trigger, el, reposition);

    // Close on outside click (deferred so the opening click doesn't trigger it)
    requestAnimationFrame(() => {
      outsideClickHandler = (e) => {
        if (!el.contains(e.target) && !trigger.contains(e.target)) {
          close();
        }
      };
      document.addEventListener("mousedown", outsideClickHandler);
    });

    // Close on Escape
    escapeHandler = (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        close();
      }
    };
    document.addEventListener("keydown", escapeHandler);
  }

  function close() {
    if (!isOpen) return;
    isOpen = false;
    el.style.display = "none";

    cleanupAutoUpdate?.();
    cleanupAutoUpdate = null;

    if (outsideClickHandler) {
      document.removeEventListener("mousedown", outsideClickHandler);
      outsideClickHandler = null;
    }
    if (escapeHandler) {
      document.removeEventListener("keydown", escapeHandler);
      escapeHandler = null;
    }

    onClose?.();
  }

  function destroy() {
    close();
    el.remove();
  }

  return {
    el,
    open,
    close,
    destroy,
    get isOpen() {
      return isOpen;
    },
  };
}
