import { ref } from "vue";
import { useLive } from "@composables/useLive.js";

const DRAG_THROTTLE_MS = 50;

/**
 * Composable for dragging pins and annotations on the Konva canvas.
 *
 * Maintains a reactive `dragOverrides` map of { [id]: { x, y } } in pixel coords.
 * Connected elements (like connections) read these overrides to update in real-time
 * during drag, following the standard Konva pattern for connected objects.
 *
 * @see https://konvajs.org/docs/sandbox/Connected_Objects.html
 */
export function useDrag({ pixelToPercent }) {
  const live = useLive();
  const isDragging = ref(false);
  // Live pixel positions during drag — connections read this to follow pins
  const dragOverrides = ref({});
  let lastDragTime = 0;

  function onDragStart(_type, id, e) {
    isDragging.value = true;
    lastDragTime = 0;
    const node = e.target;
    dragOverrides.value = {
      ...dragOverrides.value,
      [id]: { x: node.x(), y: node.y() },
    };
  }

  function onDragMove(type, id, e) {
    const node = e.target;

    // Update live position every frame — connections read this reactively
    dragOverrides.value = {
      ...dragOverrides.value,
      [id]: { x: node.x(), y: node.y() },
    };

    // Throttle server relay events
    const now = Date.now();
    if (now - lastDragTime < DRAG_THROTTLE_MS) {
      return;
    }
    lastDragTime = now;

    const pos = pixelToPercent(node.x(), node.y());
    live.pushEvent(`drag_${type}`, {
      id: String(id),
      position_x: pos.x,
      position_y: pos.y,
    });
  }

  function onDragEnd(type, id, e) {
    isDragging.value = false;
    const node = e.target;
    const pos = pixelToPercent(node.x(), node.y());

    // Keep override until server responds — prevents connection snap-back
    live.pushEvent(`move_${type}`, { id: String(id), position_x: pos.x, position_y: pos.y }, () => {
      // Server confirmed — clear override, props now have the new position
      const next = { ...dragOverrides.value };
      delete next[id];
      dragOverrides.value = next;
    });
  }

  return { isDragging, dragOverrides, onDragStart, onDragMove, onDragEnd };
}
