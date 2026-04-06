import { onMounted, ref, type Ref } from "vue";
import { useLive } from "@composables/useLive";
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

interface UseCanvasCreationOpts {
  stageRef: Ref<{
    getStage: () => { getPointerPosition: () => { x: number; y: number } | null };
  } | null>;
  stageConfig: StageConfig;
  pixelToPercent: (pixelX: number, pixelY: number) => PixelPoint;
  activeTool: Ref<string>;
  editMode: Ref<boolean>;
  canEdit: Ref<boolean>;
}

const CREATION_TOOLS = new Set(["pin", "annotation"]);

/**
 * Composable for creating pins and annotations by clicking the canvas.
 *
 * When activeTool is "pin" or "annotation", a stage click converts the pointer
 * position to world->percent coordinates and pushes the corresponding server event.
 * The server creates the element, auto-selects it, and resets the tool to "select".
 */
export function useCanvasCreation({
  stageRef: _stageRef,
  stageConfig,
  pixelToPercent,
  activeTool,
  editMode,
  canEdit,
}: UseCanvasCreationOpts) {
  const live = useLive();
  const hasPendingSheet = ref(false);

  onMounted(() => {
    live.handleEvent("pending_sheet_changed", ({ active }: { active: boolean }) => {
      hasPendingSheet.value = !!active;
    });
  });

  /**
   * Returns true if the current tool is a creation tool and handled the click.
   * Called from the stage click handler before deselection logic.
   */
  function handleCreationClick(e: KonvaEventObject<MouseEvent>): boolean {
    if (!editMode.value || !canEdit.value) {
      return false;
    }
    if (!CREATION_TOOLS.has(activeTool.value)) {
      return false;
    }

    // Only create on empty canvas clicks (target === stage)
    const stage = e.target.getStage();
    if (e.target !== stage) {
      return false;
    }

    const pointer = stage!.getPointerPosition();
    if (!pointer) {
      return false;
    }

    // Convert screen pointer -> world coords -> percent
    const worldX = (pointer.x - stageConfig.x) / stageConfig.scaleX;
    const worldY = (pointer.y - stageConfig.y) / stageConfig.scaleY;
    const pos = pixelToPercent(worldX, worldY);

    if (activeTool.value === "pin") {
      if (hasPendingSheet.value) {
        live.pushEvent("create_pin_from_sheet", {
          position_x: pos.x,
          position_y: pos.y,
        });
      } else {
        live.pushEvent("create_pin", {
          position_x: pos.x,
          position_y: pos.y,
        });
      }
      return true;
    }

    if (activeTool.value === "annotation") {
      live.pushEvent("create_annotation", {
        position_x: pos.x,
        position_y: pos.y,
      });
      return true;
    }

    return false;
  }

  return { handleCreationClick, hasPendingSheet };
}
