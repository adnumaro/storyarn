/**
 * Context menu factory for the map canvas.
 *
 * Creates a single reusable dropdown menu positioned at cursor coordinates.
 * Items are [{label, icon, action, danger}] where action is a callback.
 */

/**
 * @param {Object} hook - The MapCanvas hook instance
 * @returns {{ show(x, y, items), hide() }}
 */
export function createContextMenu(hook) {
  let menuEl = null;

  function ensureElement() {
    if (menuEl) return menuEl;

    menuEl = document.createElement("div");
    menuEl.className =
      "map-context-menu absolute z-[9999] bg-base-100 border border-base-300 rounded-lg shadow-lg py-1 min-w-[160px] hidden";
    hook.el.appendChild(menuEl);

    // Close on outside click
    document.addEventListener("click", handleOutsideClick);
    document.addEventListener("keydown", handleEscape);

    return menuEl;
  }

  function handleOutsideClick(e) {
    if (menuEl && !menuEl.contains(e.target)) {
      hide();
    }
  }

  function handleEscape(e) {
    if (e.key === "Escape") hide();
  }

  /**
   * Shows the context menu at (x, y) container-relative coordinates.
   * @param {number} x - X position relative to the hook element
   * @param {number} y - Y position relative to the hook element
   * @param {Array} items - [{label, icon?, action, danger?}]
   */
  function show(x, y, items) {
    const el = ensureElement();

    // Build menu items
    el.innerHTML = "";
    for (const item of items) {
      if (item.separator) {
        const sep = document.createElement("div");
        sep.className = "border-t border-base-300 my-1";
        el.appendChild(sep);
        continue;
      }

      const btn = document.createElement("button");
      btn.type = "button";
      const isDisabled = item.disabled === true;
      btn.className = `flex items-center gap-2 w-full px-3 py-1.5 text-sm text-left transition-colors ${
        isDisabled
          ? "text-base-content/30 cursor-not-allowed"
          : item.danger
            ? "text-error hover:bg-error/10"
            : "text-base-content hover:bg-base-200"
      }`;
      btn.textContent = item.label;
      if (isDisabled) {
        btn.disabled = true;
        if (item.tooltip) btn.title = item.tooltip;
      } else {
        btn.addEventListener("click", (e) => {
          e.stopPropagation();
          hide();
          if (item.action) item.action();
        });
      }
      el.appendChild(btn);
    }

    // Position — make sure it stays within the container
    el.style.left = `${x}px`;
    el.style.top = `${y}px`;
    el.classList.remove("hidden");

    // Adjust if overflowing
    requestAnimationFrame(() => {
      const rect = el.getBoundingClientRect();
      const container = hook.el.getBoundingClientRect();

      if (rect.right > container.right) {
        el.style.left = `${x - (rect.right - container.right) - 4}px`;
      }
      if (rect.bottom > container.bottom) {
        el.style.top = `${y - (rect.bottom - container.bottom) - 4}px`;
      }
    });
  }

  function hide() {
    if (menuEl) {
      menuEl.classList.add("hidden");
    }
  }

  function destroy() {
    document.removeEventListener("click", handleOutsideClick);
    document.removeEventListener("keydown", handleEscape);
    if (menuEl) {
      menuEl.remove();
      menuEl = null;
    }
  }

  return { show, hide, destroy };
}
