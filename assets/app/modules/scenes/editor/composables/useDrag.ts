import { onBeforeUnmount, ref } from "vue";
import { useLive } from "@shared/composables/useLive";
import type { KonvaEventObject } from "konva/lib/Node";

interface PixelPoint {
  x: number;
  y: number;
}

type DraggableElementType = "annotation" | "pin";

interface UseDragOpts {
  pixelToPercent: (pixelX: number, pixelY: number) => PixelPoint;
  shouldTrackDrag?: (type: DraggableElementType, id: number | string) => boolean;
  onCommit?: (type: DraggableElementType, id: number | string, position: PixelPoint) => void;
}

const REMOTE_DRAG_RELAY_MS = 120;
const OVERRIDE_CLEAR_TIMEOUT_MS = 5000;

function normalizeDragType(type: string): DraggableElementType | null {
  if (type === "annotation" || type === "pin") return type;
  return null;
}

/**
 * Composable for dragging pins and annotations on the Konva canvas.
 *
 * Maintains a reactive `dragOverrides` map of { [id]: { x, y } } in pixel coords.
 * Connected elements (like connections) read these overrides to update in real-time
 * during drag, following the standard Konva pattern for connected objects.
 *
 * @see https://konvajs.org/docs/sandbox/Connected_Objects.html
 */
export function useDrag({ pixelToPercent, shouldTrackDrag, onCommit }: UseDragOpts) {
  const live = useLive();
  const isDragging = ref(false);
  // Live pixel positions during drag -- connections read this to follow pins
  const dragOverrides = ref<Record<string | number, PixelPoint>>({});
  const clearTimers = new Map<string | number, number>();
  let animationFrame: number | null = null;
  let pendingOverride: { id: number | string; position: PixelPoint } | null = null;
  let pendingRemoteRelay: {
    type: DraggableElementType;
    id: number | string;
    position: PixelPoint;
  } | null = null;
  let remoteRelayTimer: number | null = null;
  let tracksCurrentDrag = false;

  function clearScheduledFrame(): void {
    if (animationFrame === null) return;
    window.cancelAnimationFrame(animationFrame);
    animationFrame = null;
  }

  function clearRemoteRelayTimer(): void {
    if (remoteRelayTimer === null) return;
    window.clearTimeout(remoteRelayTimer);
    remoteRelayTimer = null;
  }

  function flushRemoteRelay(): void {
    const relay = pendingRemoteRelay;
    pendingRemoteRelay = null;
    remoteRelayTimer = null;

    if (!relay) return;

    live.pushEvent(`drag_${relay.type}`, {
      id: String(relay.id),
      position_x: relay.position.x,
      position_y: relay.position.y,
    });
  }

  function applyDragOverride(id: number | string, position: PixelPoint): void {
    dragOverrides.value = {
      ...dragOverrides.value,
      [id]: position,
    };
  }

  function scheduleDragOverride(id: number | string, position: PixelPoint): void {
    pendingOverride = { id, position };

    if (animationFrame !== null) return;

    animationFrame = window.requestAnimationFrame(() => {
      animationFrame = null;

      if (!pendingOverride) return;

      applyDragOverride(pendingOverride.id, pendingOverride.position);
      pendingOverride = null;
    });
  }

  function relayRemoteDrag(
    type: DraggableElementType,
    id: number | string,
    position: PixelPoint,
  ): void {
    pendingRemoteRelay = { type, id, position };

    if (remoteRelayTimer !== null) return;

    remoteRelayTimer = window.setTimeout(flushRemoteRelay, REMOTE_DRAG_RELAY_MS);
  }

  function clearDragOverride(id: number | string): void {
    const timer = clearTimers.get(id);
    if (timer) window.clearTimeout(timer);
    clearTimers.delete(id);

    const next = { ...dragOverrides.value };
    delete next[id];
    dragOverrides.value = next;
  }

  function scheduleOverrideCleanup(id: number | string): void {
    const existingTimer = clearTimers.get(id);
    if (existingTimer) window.clearTimeout(existingTimer);

    clearTimers.set(
      id,
      window.setTimeout(() => clearDragOverride(id), OVERRIDE_CLEAR_TIMEOUT_MS),
    );
  }

  function onDragStart(rawType: string, id: number | string, e: KonvaEventObject<DragEvent>): void {
    const type = normalizeDragType(rawType);
    if (!type) return;

    isDragging.value = true;
    tracksCurrentDrag = shouldTrackDrag?.(type, id) ?? false;

    if (!tracksCurrentDrag) return;

    const node = e.target;
    applyDragOverride(id, { x: node.x(), y: node.y() });
  }

  function onDragMove(rawType: string, id: number | string, e: KonvaEventObject<DragEvent>): void {
    const type = normalizeDragType(rawType);
    if (!type) return;

    const node = e.target;
    const pixelPosition = { x: node.x(), y: node.y() };
    const percentPosition = pixelToPercent(node.x(), node.y());

    if (tracksCurrentDrag) {
      scheduleDragOverride(id, pixelPosition);
    }

    relayRemoteDrag(type, id, percentPosition);
  }

  function onDragEnd(rawType: string, id: number | string, e: KonvaEventObject<DragEvent>): void {
    const type = normalizeDragType(rawType);
    if (!type) return;

    isDragging.value = false;
    clearScheduledFrame();
    clearRemoteRelayTimer();
    pendingRemoteRelay = null;

    const node = e.target;
    const pixelPosition = { x: node.x(), y: node.y() };
    const pos = pixelToPercent(node.x(), node.y());

    if (tracksCurrentDrag) {
      applyDragOverride(id, pixelPosition);
      scheduleOverrideCleanup(id);
    }

    onCommit?.(type, id, pos);

    live.pushEvent(`move_${type}`, { id: String(id), position_x: pos.x, position_y: pos.y }, () => {
      clearDragOverride(id);
    });

    tracksCurrentDrag = false;
  }

  onBeforeUnmount(() => {
    clearScheduledFrame();
    clearRemoteRelayTimer();

    for (const timer of clearTimers.values()) {
      window.clearTimeout(timer);
    }

    clearTimers.clear();
  });

  return { isDragging, dragOverrides, onDragStart, onDragMove, onDragEnd };
}
