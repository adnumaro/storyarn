/**
 * Minimap toggle for the flow canvas editor.
 *
 * Adds an expand/collapse button (LayoutGrid icon) that shows or hides the
 * Rete minimap, matching the scene editor's minimap toggle pattern.
 */

import { createElement, LayoutGrid, Maximize2 } from "lucide";
import { AreaExtensions } from "rete-area-plugin";

/** CSS injected into the rete-minimap Shadow DOM to fix dark mode colors. */
const MINIMAP_THEME_CSS = `
  .minimap {
    background: color-mix(in oklch, var(--color-base-200, #f3f4f6) 90%, transparent) !important;
    border-color: var(--color-base-300, #d1d5db) !important;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15) !important;
  }
  .mini-node {
    background: color-mix(in oklch, var(--color-primary, #6e88ff) 60%, transparent) !important;
    border-color: var(--color-base-300, rgb(192 206 212 / 60%)) !important;
  }
`;

/**
 * Creates a minimap toggle for the flow editor.
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {{ init, destroy }}
 */
export function createMinimapToggle(hook) {
  let collapsed = false;
  let container = null;
  let themed = false;
  let fitTransitionTimer = null;

  function init() {
    container = document.createElement("div");
    container.className = "map-minimap";
    container.style.cssText = `
      position: absolute;
      bottom: 24px;
      right: 24px;
      z-index: 10;
    `;

    const fitBtn = document.createElement("button");
    fitBtn.className = "map-minimap-toggle";
    fitBtn.type = "button";
    fitBtn.title = "Fit all nodes in view";
    fitBtn.appendChild(createElement(Maximize2, { width: 14, height: 14 }));
    fitBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      const nodes = hook.editor.getNodes();
      if (nodes.length === 0) return;

      // Temporarily enable a smooth CSS transition on Rete's content holder
      const holder = hook.area.area?.content?.holder;
      if (holder) {
        clearTimeout(fitTransitionTimer);
        holder.style.transition = "transform 0.25s cubic-bezier(0.25, 0.46, 0.45, 0.94)";
        fitTransitionTimer = setTimeout(() => {
          holder.style.transition = "";
          fitTransitionTimer = null;
        }, 270);
      }

      AreaExtensions.zoomAt(hook.area, nodes);
    });
    container.appendChild(fitBtn);

    const btn = document.createElement("button");
    btn.className = "map-minimap-toggle";
    btn.type = "button";
    btn.title = "Toggle minimap";
    btn.appendChild(createElement(LayoutGrid, { width: 14, height: 14 }));
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      toggle();
    });
    container.appendChild(btn);

    hook.el.appendChild(container);

    // Apply initial visibility (expanded by default).
    // Retry a few frames in case Rete hasn't rendered the element yet.
    waitForMinimap(10);
  }

  /** Polls for the rete-minimap element and applies initial state once found. */
  function waitForMinimap(attempts) {
    const el = hook.el.querySelector("rete-minimap");
    if (el) {
      injectTheme(el);
      applyVisibility();
    } else if (attempts > 0) {
      requestAnimationFrame(() => waitForMinimap(attempts - 1));
    }
  }

  /** Injects theme-aware CSS into the minimap's Shadow DOM (once). */
  function injectTheme(reteMinimap) {
    if (themed || !reteMinimap.shadowRoot) return;
    const style = document.createElement("style");
    style.textContent = MINIMAP_THEME_CSS;
    reteMinimap.shadowRoot.appendChild(style);
    themed = true;
  }

  function toggle() {
    collapsed = !collapsed;
    applyVisibility();
  }

  /** Shows or hides the rete-minimap element. Button always stays at bottom. */
  function applyVisibility() {
    const reteMinimap = hook.el.querySelector("rete-minimap");
    if (reteMinimap) {
      injectTheme(reteMinimap);
      reteMinimap.style.display = collapsed ? "none" : "";
      reteMinimap.style.bottom = "";
      reteMinimap.style.top = "";

      if (!collapsed) {
        // The inner .minimap div in the Shadow DOM has bottom: 24px via its own CSS.
        // Override it directly so the map sits above the toggle button.
        const inner = reteMinimap.shadowRoot?.querySelector(".minimap");
        if (inner) inner.style.bottom = "68px";
      }
    }

    // Button always stays at bottom
    container.style.bottom = "24px";
    container.style.right = "24px";
  }

  function destroy() {
    container?.remove();
    container = null;
  }

  return { init, destroy };
}
