import { ref, type Ref } from "vue";
import { useLive } from "@composables/useLive";
import type { KonvaEventObject } from "konva/lib/Node";

const DRAG_THROTTLE_MS = 50;

interface Vertex {
  x: number;
  y: number;
}

interface PixelPoint {
  x: number;
  y: number;
}

interface ZoneData {
  id: number | string;
  vertices: Vertex[] | null;
  locked: boolean;
}

interface EntityLock {
  userId: number | string;
}

interface ZoneDragOverride {
  id: number | string;
  vertices: Vertex[];
}

interface StageConfig {
  x: number;
  y: number;
  scaleX: number;
  scaleY: number;
}

interface UseZoneDragOpts {
  stageRef: Ref<{ getStage: () => { getPointerPosition: () => PixelPoint | null } | null } | null>;
  stageConfig: StageConfig;
  pixelToPercent: (pixelX: number, pixelY: number) => PixelPoint;
  zones: Ref<ZoneData[]>;
  selectedType: Ref<string | null>;
  selectedId: Ref<number | string | null>;
  editMode: Ref<boolean>;
  canEdit: Ref<boolean>;
  entityLocks: Ref<Record<string, EntityLock>>;
  currentUserId: Ref<number | string>;
}

/**
 * Composable for dragging zones by moving all vertices by the same delta.
 *
 * Zones are Konva v-line polygons (not groups with x/y), so we can't use
 * Konva's native draggable. Instead we track mousedown->mousemove->mouseup
 * on the selected zone and compute a pixel delta -> percent delta to offset
 * all vertices.
 */
export function useZoneDrag({
  stageRef,
  stageConfig,
  pixelToPercent,
  zones,
  selectedType,
  selectedId,
  editMode,
  canEdit,
  entityLocks,
  currentUserId,
}: UseZoneDragOpts) {
  const live = useLive();
  const isDraggingZone = ref(false);
  // Override vertices during drag (percent coords) -- zones composable reads this
  const zoneDragOverride = ref<ZoneDragOverride | null>(null);
  let dragStartWorld: PixelPoint | null = null;
  let dragOriginalVertices: Vertex[] | null = null;
  let dragZoneId: number | string | null = null;
  let lastDragTime = 0;

  function getWorldPointer(): PixelPoint | null {
    const stage = stageRef.value?.getStage?.();
    if (!stage) {
      return null;
    }
    const pointer = stage.getPointerPosition();
    if (!pointer) {
      return null;
    }
    return {
      x: (pointer.x - stageConfig.x) / stageConfig.scaleX,
      y: (pointer.y - stageConfig.y) / stageConfig.scaleY,
    };
  }

  /**
   * Called on mousedown on a zone group. Starts drag if the zone is selected
   * and editable.
   */
  function onZoneMouseDown(zoneId: number | string, e?: KonvaEventObject<MouseEvent>): void {
    if (!editMode.value || !canEdit.value) {
      return;
    }
    if (selectedType.value !== "zone" || selectedId.value !== zoneId) {
      return;
    }

    // Check lock
    const lock = entityLocks.value[String(zoneId)];
    if (lock && String(lock.userId) !== String(currentUserId.value)) {
      return;
    }

    const zone = zones.value.find((z) => z.id === zoneId);
    if (!zone || zone.locked) {
      return;
    }

    const world = getWorldPointer();
    if (!world) {
      return;
    }

    dragStartWorld = world;
    dragOriginalVertices = [...(zone.vertices || [])];
    dragZoneId = zoneId;
    isDraggingZone.value = true;
    lastDragTime = 0;

    // Prevent stage pan during zone drag
    if (e?.evt) {
      e.evt.preventDefault();
    }
  }

  /**
   * Called on stage mousemove. Updates the drag override if dragging.
   */
  function onZoneDragMove(): void {
    if (!isDraggingZone.value) {
      return;
    }

    const world = getWorldPointer();
    if (!world || !dragStartWorld) {
      return;
    }

    const current = pixelToPercent(world.x, world.y);
    const start = pixelToPercent(dragStartWorld.x, dragStartWorld.y);
    const dx = current.x - start.x;
    const dy = current.y - start.y;

    const newVertices = dragOriginalVertices!.map((v) => ({
      x: v.x + dx,
      y: v.y + dy,
    }));

    zoneDragOverride.value = { id: dragZoneId!, vertices: newVertices };

    // Throttle ephemeral server events
    const now = Date.now();
    if (now - lastDragTime < DRAG_THROTTLE_MS) {
      return;
    }
    lastDragTime = now;

    live.pushEvent("drag_zone", {
      id: String(dragZoneId),
      vertices: newVertices,
    });
  }

  /**
   * Called on stage mouseup. Persists the final vertex positions.
   * Keeps the override until the server confirms (prevents snap-back).
   */
  function onZoneDragEnd(): void {
    if (!isDraggingZone.value) {
      return;
    }

    const override = zoneDragOverride.value;
    isDraggingZone.value = false;

    if (!override) {
      return;
    }

    dragStartWorld = null;
    dragOriginalVertices = null;
    dragZoneId = null;

    // Keep override visible until server confirms with new props
    live.pushEvent(
      "update_zone_vertices",
      { id: String(override.id), vertices: override.vertices },
      () => {
        zoneDragOverride.value = null;
      },
    );
  }

  return {
    isDraggingZone,
    zoneDragOverride,
    onZoneMouseDown,
    onZoneDragMove,
    onZoneDragEnd,
  };
}
