/**
 * Marquee (drag-rectangle) selection for the flow editor.
 *
 * Active only while `activeFlowTool.value === "select"`. Intercepts
 * pointerdown on empty canvas in capture phase, stopping rete's native
 * pan, and draws a translucent overlay rectangle. On pointerup, every
 * node whose bounding box intersects the marquee is fed into the rete
 * selector. Sequence-type nodes are selectable (they're containers
 * but nothing special from a selection standpoint after Phase 1).
 *
 * Shift or Ctrl while dragging accumulates into the current selection;
 * no modifier replaces it.
 *
 * Returns a teardown function that removes all listeners and any stray
 * overlay — call from `onUnmounted` in the composable that set it up.
 */

import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";
import { watch } from "vue";

import type { FlowAreaExtra, FlowSchemes } from "../lib/rete-schemes";
import { activeFlowTool } from "../lib/flow-tool-state";
import { activeFlowPlacement } from "../lib/flow-placement-state";
import type { SelectionHandles } from "./reteSetup";

interface MarqueeOptions {
  containerEl: HTMLElement;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  editor: NodeEditor<FlowSchemes>;
  selection: SelectionHandles;
}

interface RectBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export function createFlowMarquee({
  containerEl,
  area,
  editor,
  selection,
}: MarqueeOptions): () => void {
  let overlay: HTMLDivElement | null = null;
  let startX = 0;
  let startY = 0;
  let dragging = false;

  function canStartMarquee(e: PointerEvent): boolean {
    return !activeFlowPlacement.value && activeFlowTool.value === "select" && e.button === 0;
  }

  function onPointerDown(e: PointerEvent): void {
    // Only left button triggers marquee; middle/right reserved for future panning
    if (!canStartMarquee(e)) return;

    const target = e.target as HTMLElement | null;
    if (!target) return;

    // If the click starts on a rete node, socket, connection, or sequence,
    // let rete's own handlers run (node drag, click-select, connection draw, etc.).
    if (
      target.closest("[data-testid='node']") ||
      target.closest("[data-testid='flow-sequence']") ||
      target.closest(".connection") ||
      target.closest(".socket") ||
      target.closest("[data-flow-interactive='true']")
    ) {
      return;
    }

    // If the context menu is open, let this click propagate so the
    // rete-context-menu-plugin's "click outside to close" handler fires.
    // Otherwise `stopImmediatePropagation` below would trap the dismissal
    // and the menu would stay open forever.
    if (document.querySelector('[data-testid="flow-context-menu"]')) {
      return;
    }

    // Block rete's native area pan for this drag.
    e.stopImmediatePropagation();
    e.preventDefault();

    const rect = containerEl.getBoundingClientRect();
    startX = e.clientX - rect.left;
    startY = e.clientY - rect.top;

    overlay = document.createElement("div");
    overlay.className = "flow-marquee-overlay";
    overlay.style.cssText = [
      "position: absolute",
      `left: ${startX}px`,
      `top: ${startY}px`,
      "width: 0",
      "height: 0",
      "border: 1px solid hsl(var(--primary))",
      "background: hsl(var(--primary) / 0.08)",
      "pointer-events: none",
      "z-index: 9999",
    ].join("; ");
    containerEl.appendChild(overlay);

    dragging = true;
    document.addEventListener("pointermove", onPointerMove);
    document.addEventListener("pointerup", onPointerUp, { once: true });
  }

  function onPointerMove(e: PointerEvent): void {
    if (!dragging || !overlay) return;
    const rect = containerEl.getBoundingClientRect();
    const curX = e.clientX - rect.left;
    const curY = e.clientY - rect.top;
    const left = Math.min(startX, curX);
    const top = Math.min(startY, curY);
    const width = Math.abs(curX - startX);
    const height = Math.abs(curY - startY);
    overlay.style.left = `${left}px`;
    overlay.style.top = `${top}px`;
    overlay.style.width = `${width}px`;
    overlay.style.height = `${height}px`;
  }

  function onPointerUp(e: PointerEvent): void {
    document.removeEventListener("pointermove", onPointerMove);
    if (!dragging) return;
    dragging = false;

    const marqueeRect = finalizeOverlay();
    if (!marqueeRect) return;

    if (!(e.shiftKey || e.ctrlKey || e.metaKey)) {
      selection.selector.unselectAll();
    }

    selectNodesInsideMarquee(marqueeRect);
  }

  function finalizeOverlay(): DOMRect | null {
    const rect = overlay?.getBoundingClientRect() ?? null;
    if (overlay) {
      overlay.remove();
      overlay = null;
    }
    if (!rect || rect.width < 2 || rect.height < 2) return null;
    return rect;
  }

  function selectNodesInsideMarquee(marqueeRect: DOMRect): void {
    for (const [nodeId, view] of area.nodeViews) {
      const el = view.element as HTMLElement | undefined;
      if (!el) continue;
      const nodeRect = el.getBoundingClientRect();
      // Sequence bboxes wrap their children, so a marquee over the interior of
      // a sequence would otherwise also pick up the sequence itself. That breaks
      // subsequent drag (`reassignParent` orphans every child because the
      // sequence is excluded as overlay candidate) and the context menu's
      // multi-delete (iterates all selected ids). Require full containment for
      // sequences — matches Figma frame selection.
      const node = editor.getNode(nodeId);
      const isSequence = node?.nodeType === "sequence";
      const matches = isSequence
        ? rectFullyContains(marqueeRect, nodeRect)
        : rectsIntersect(marqueeRect, nodeRect);
      if (matches) {
        void selection.select(nodeId, true);
      }
    }
  }

  function rectsIntersect(a: RectBounds | DOMRect, b: DOMRect): boolean {
    return !(a.right < b.left || a.left > b.right || a.bottom < b.top || a.top > b.bottom);
  }

  function rectFullyContains(outer: RectBounds | DOMRect, inner: DOMRect): boolean {
    return (
      outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom
    );
  }

  function attach(): void {
    containerEl.addEventListener("pointerdown", onPointerDown, { capture: true });
  }

  function detach(): void {
    containerEl.removeEventListener("pointerdown", onPointerDown, { capture: true });
    document.removeEventListener("pointermove", onPointerMove);
    if (overlay) {
      overlay.remove();
      overlay = null;
      dragging = false;
    }
  }

  // Active only while in "select" mode. Toggling to "pan" detaches so rete's
  // native pan is restored without an extra "is select?" guard on every event.
  const stopWatch = watch(
    activeFlowTool,
    (tool, prev) => {
      if (tool === "select" && prev !== "select") attach();
      if (tool !== "select" && prev === "select") detach();
    },
    { immediate: true },
  );

  return () => {
    stopWatch();
    detach();
  };
}
