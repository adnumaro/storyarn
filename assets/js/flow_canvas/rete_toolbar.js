/**
 * Floating toolbar positioning controller for the flow canvas.
 *
 * Positions the #flow-floating-toolbar element above the selected node.
 * The toolbar content is rendered server-side (HEEx) and patched by LiveView.
 * This module only handles show/hide/position logic.
 */

const MARGIN = 8;
const TOOLBAR_OFFSET_Y = 12;

/**
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {{ show(nodeDbId: number), hide(), reposition(), setDragging(dragging: boolean) }}
 */
export function createFlowFloatingToolbar(hook) {
  let currentNodeDbId = null;
  let isDragging = false;

  function getToolbarEl() {
    return document.getElementById("flow-floating-toolbar");
  }

  function show(nodeDbId) {
    currentNodeDbId = nodeDbId;
    isDragging = false;
    requestAnimationFrame(() => position());
  }

  function hide() {
    currentNodeDbId = null;
    const el = getToolbarEl();
    if (el) el.classList.remove("toolbar-visible");
  }

  function reposition() {
    if (!currentNodeDbId || isDragging) return;
    position();
  }

  function setDragging(dragging) {
    isDragging = dragging;
    const el = getToolbarEl();
    if (!el) return;
    if (dragging) {
      el.classList.remove("toolbar-visible");
    } else if (currentNodeDbId) {
      requestAnimationFrame(() => position());
    }
  }

  function position() {
    const el = getToolbarEl();
    if (!el || !currentNodeDbId) return;

    // Find the Rete node view element
    const reteNode = hook.nodeMap.get(currentNodeDbId);
    if (!reteNode) {
      el.classList.remove("toolbar-visible");
      return;
    }

    const nodeView = hook.area.nodeViews.get(reteNode.id);
    if (!nodeView) {
      el.classList.remove("toolbar-visible");
      return;
    }

    const nodeRect = nodeView.element.getBoundingClientRect();
    const canvas = hook.el.parentElement; // <div class="flex-1 relative bg-base-200">
    const canvasRect = canvas.getBoundingClientRect();

    // Temporarily make visible to measure
    const wasVisible = el.classList.contains("toolbar-visible");
    if (!wasVisible) {
      el.style.visibility = "hidden";
      el.style.opacity = "0";
      el.classList.add("toolbar-visible");
    }

    const toolbarRect = el.getBoundingClientRect();
    const toolbarW = toolbarRect.width;
    const toolbarH = toolbarRect.height;

    // Position above node, centered horizontally
    let left = nodeRect.left + nodeRect.width / 2 - canvasRect.left - toolbarW / 2;
    let top = nodeRect.top - canvasRect.top - toolbarH - TOOLBAR_OFFSET_Y;

    // Clamp horizontally
    left = Math.max(MARGIN, Math.min(left, canvasRect.width - toolbarW - MARGIN));

    // Flip below if too close to top
    if (top < MARGIN) {
      top = nodeRect.bottom - canvasRect.top + TOOLBAR_OFFSET_Y;
    }

    el.style.left = `${Math.round(left)}px`;
    el.style.top = `${Math.round(top)}px`;

    el.style.visibility = "";
    el.style.opacity = "";
  }

  return { show, hide, reposition, setDragging };
}
