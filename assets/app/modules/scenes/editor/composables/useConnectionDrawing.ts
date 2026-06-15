import { computed, onMounted, onUnmounted, ref, type Ref } from "vue";
import { useLive } from "@shared/composables/useLive";
import type { KonvaEventObject } from "konva/lib/Node";

interface PixelPoint {
  x: number;
  y: number;
}

interface StageConfig {
  x: number;
  y: number;
  scaleX: number;
  scaleY: number;
}

interface PinData {
  id: number | string;
  positionX: number;
  positionY: number;
}

interface UseConnectionDrawingOpts {
  stageRef: Ref<{ getStage: () => { getPointerPosition: () => PixelPoint | null } | null } | null>;
  stageConfig: StageConfig;
  pixelToPercent: (pixelX: number, pixelY: number) => PixelPoint;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  activeTool: Ref<string>;
  editMode: Ref<boolean>;
  canEdit: Ref<boolean>;
  pins: Ref<PinData[]>;
}

const SOURCE_HIGHLIGHT_COLOR = "#6366f1";
const TARGET_HIGHLIGHT_COLOR = "#22c55e";
const PREVIEW_STROKE = "#6366f1";

/**
 * Composable for drawing connections between pins.
 *
 * State machine: idle -> source_selected -> (click target pin or map point) -> create_connection.
 * While source is selected, a dashed preview line follows the cursor.
 * Escape cancels.
 */
export function useConnectionDrawing({
  stageRef,
  stageConfig,
  pixelToPercent,
  percentToPixel,
  activeTool,
  editMode,
  canEdit,
  pins,
}: UseConnectionDrawingOpts) {
  const live = useLive();

  const sourcePinId = ref<number | string | null>(null);
  const sourcePoint = ref<PixelPoint | null>(null);
  const cursorPos = ref<PixelPoint | null>(null);
  const hoveredPinId = ref<number | string | null>(null);

  const isDrawingConnection = computed(
    () =>
      activeTool.value === "connector" &&
      (sourcePinId.value !== null || sourcePoint.value !== null),
  );

  /**
   * Handle click on a pin while connector tool is active.
   * Returns true if handled.
   */
  function handlePinClickForConnection(
    pinId: number | string,
    e?: KonvaEventObject<MouseEvent>,
  ): boolean {
    if (activeTool.value !== "connector") {
      return false;
    }
    if (!editMode.value || !canEdit.value) {
      return false;
    }
    if (e) {
      e.cancelBubble = true;
    }

    if (sourcePinId.value === null && sourcePoint.value === null) {
      // First click: select source
      sourcePinId.value = pinId;
      return true;
    }

    // Second click: select target
    if (pinId === sourcePinId.value) {
      return true;
    } // can't connect to self

    if (sourcePinId.value !== null) {
      live.pushEvent("create_connection", {
        from_pin_id: String(sourcePinId.value),
        to_pin_id: String(pinId),
      });
    } else if (sourcePoint.value) {
      live.pushEvent("create_connection", {
        to_pin_id: String(pinId),
        waypoints: [routePoint(sourcePoint.value)],
      });
    }

    cancel();
    return true;
  }

  /**
   * Handle empty-canvas clicks while drawing routes with free points.
   * Returns true if handled (consumed the click).
   */
  function handleStageClickForConnection(e: KonvaEventObject<MouseEvent>): boolean {
    if (activeTool.value !== "connector") {
      return false;
    }
    if (!editMode.value || !canEdit.value) {
      return false;
    }
    const stage = e.target.getStage();
    if (e.target !== stage) {
      return false;
    }

    const point = pointerPercentPoint();
    if (!point) {
      return false;
    }

    if (!hasSource()) {
      sourcePoint.value = point;
      return true;
    }

    createRouteToFreePoint(point);
    cancel();
    return true;
  }

  function hasSource(): boolean {
    return sourcePinId.value !== null || sourcePoint.value !== null;
  }

  function createRouteToFreePoint(point: PixelPoint): void {
    if (sourcePinId.value !== null) {
      live.pushEvent("create_connection", {
        from_pin_id: String(sourcePinId.value),
        waypoints: [routePoint(point)],
      });
      return;
    }

    if (sourcePoint.value) {
      live.pushEvent("create_connection", {
        waypoints: [routePoint(sourcePoint.value), routePoint(point)],
      });
    }
  }

  function cancel(): void {
    sourcePinId.value = null;
    sourcePoint.value = null;
    cursorPos.value = null;
    hoveredPinId.value = null;
  }

  function routePoint(point: PixelPoint): Record<string, number | boolean> {
    return {
      x: Math.round(point.x * 100) / 100,
      y: Math.round(point.y * 100) / 100,
      stop: true,
    };
  }

  function pointerPercentPoint(): PixelPoint | null {
    const stage = stageRef.value?.getStage?.();
    if (!stage) {
      return null;
    }
    const pointer = stage.getPointerPosition();
    if (!pointer) {
      return null;
    }
    const worldX = (pointer.x - stageConfig.x) / stageConfig.scaleX;
    const worldY = (pointer.y - stageConfig.y) / stageConfig.scaleY;
    return pixelToPercent(worldX, worldY);
  }

  // Track cursor + hovered pin via proximity (avoids per-pin mouseenter/mouseleave events)
  const PIN_HOVER_THRESHOLD = 25;

  function onMouseMove(): void {
    if (!isDrawingConnection.value) {
      return;
    }
    const stage = stageRef.value?.getStage?.();
    if (!stage) {
      return;
    }
    const pointer = stage.getPointerPosition();
    if (!pointer) {
      return;
    }
    const worldX = (pointer.x - stageConfig.x) / stageConfig.scaleX;
    const worldY = (pointer.y - stageConfig.y) / stageConfig.scaleY;
    cursorPos.value = { x: worldX, y: worldY };

    // Find closest pin to cursor for target highlight
    let closest: number | string | null = null;
    let closestDist = PIN_HOVER_THRESHOLD;
    for (const pin of pins.value) {
      if (pin.id === sourcePinId.value) {
        continue;
      }
      const p = percentToPixel(pin.positionX, pin.positionY);
      const dx = worldX - p.x;
      const dy = worldY - p.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < closestDist) {
        closest = pin.id;
        closestDist = dist;
      }
    }
    hoveredPinId.value = closest;
  }

  // Escape cancels
  function onKeyDown(e: KeyboardEvent): void {
    if (e.key === "Escape" && isDrawingConnection.value) {
      e.preventDefault();
      cancel();
    }
  }

  onMounted(() => window.addEventListener("keydown", onKeyDown));
  onUnmounted(() => window.removeEventListener("keydown", onKeyDown));

  // Preview line from source point to cursor
  const previewLine = computed<number[] | null>(() => {
    if (!isDrawingConnection.value || !cursorPos.value) {
      return null;
    }

    const from =
      sourcePinId.value !== null
        ? pins.value.find((p) => p.id === sourcePinId.value)
        : sourcePoint.value;

    if (!from) return null;

    const start =
      sourcePinId.value !== null
        ? percentToPixel((from as PinData).positionX, (from as PinData).positionY)
        : percentToPixel((from as PixelPoint).x, (from as PixelPoint).y);
    return [start.x, start.y, cursorPos.value.x, cursorPos.value.y];
  });

  return {
    sourcePinId,
    hoveredPinId,
    isDrawingConnection,
    handlePinClickForConnection,
    handleStageClickForConnection,
    onMouseMove,
    previewLine,
    SOURCE_HIGHLIGHT_COLOR,
    TARGET_HIGHLIGHT_COLOR,
    PREVIEW_STROKE,
  };
}
