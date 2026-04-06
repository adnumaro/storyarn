import { computed, onMounted, onUnmounted, ref, type Ref } from "vue";
import { useLive } from "@composables/useLive";
import { getShapePreset } from "../lib/shape-presets";
import type { KonvaEventObject } from "konva/lib/Node";

const PRESET_TOOLS = new Set(["rectangle", "triangle", "circle"]);
const CLOSE_THRESHOLD_PX = 12;
const VERTEX_RADIUS = 5;
const _GHOST_FILL = "rgba(99,102,241,0.15)";
const GHOST_STROKE = "#6366f1";
const VERTEX_FILL = "#6366f1";
const _PREVIEW_STROKE = "#6366f1";

interface Vertex {
  x: number;
  y: number;
}

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

interface VertexConfig {
  x: number;
  y: number;
  radius: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
  listening: boolean;
}

interface DrawingOverlay {
  ghostPoints: number[];
  previewLine: number[] | null;
  closeLine: number[] | null;
  vertexConfigs: VertexConfig[];
}

interface UseZoneDrawingOpts {
  stageRef: Ref<{ getStage: () => { getPointerPosition: () => PixelPoint | null } | null } | null>;
  stageConfig: StageConfig;
  pixelToPercent: (pixelX: number, pixelY: number) => PixelPoint;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  activeTool: Ref<string>;
  editMode: Ref<boolean>;
  canEdit: Ref<boolean>;
}

/**
 * Composable for zone creation: shape presets (single-click) and freeform drawing.
 *
 * Presets: click canvas -> generate vertices from preset -> push create_zone.
 * Freeform: click adds vertices, close near first vertex or double-click to finish,
 * Escape cancels.
 */
export function useZoneDrawing({
  stageRef,
  stageConfig,
  pixelToPercent,
  percentToPixel,
  activeTool,
  editMode,
  canEdit,
}: UseZoneDrawingOpts) {
  const live = useLive();

  // Freeform drawing state (percent coordinates)
  const drawingVertices = ref<Vertex[]>([]);
  // Live cursor position in pixels (for preview line)
  const cursorPos = ref<PixelPoint | null>(null);
  const isDrawing = computed(() => drawingVertices.value.length > 0);

  /**
   * Handle a stage click for zone creation.
   * Returns true if handled.
   */
  function handleZoneCreationClick(e: KonvaEventObject<MouseEvent>): boolean {
    if (!editMode.value || !canEdit.value) {
      return false;
    }
    const tool = activeTool.value;

    // Only handle zone tools
    if (!PRESET_TOOLS.has(tool) && tool !== "freeform") {
      return false;
    }

    // Only on empty canvas
    const stage = e.target.getStage();
    if (e.target !== stage) {
      return false;
    }

    const pointer = stage!.getPointerPosition();
    if (!pointer) {
      return false;
    }

    const worldX = (pointer.x - stageConfig.x) / stageConfig.scaleX;
    const worldY = (pointer.y - stageConfig.y) / stageConfig.scaleY;
    const pos = pixelToPercent(worldX, worldY);

    // Preset tools: single click creates the zone
    const presetFn = getShapePreset(tool);
    if (presetFn) {
      const vertices = presetFn(pos.x, pos.y);
      live.pushEvent("create_zone", { vertices });
      return true;
    }

    // Freeform tool: add vertex
    if (tool === "freeform") {
      addFreeformVertex(pos, worldX, worldY);
      return true;
    }

    return false;
  }

  function addFreeformVertex(pos: Vertex, worldX: number, worldY: number): void {
    const verts = drawingVertices.value;

    // Check if closing: click near first vertex
    if (verts.length >= 3) {
      const first = percentToPixel(verts[0].x, verts[0].y);
      const dx = worldX - first.x;
      const dy = worldY - first.y;
      if (Math.sqrt(dx * dx + dy * dy) < CLOSE_THRESHOLD_PX) {
        finishFreeform();
        return;
      }
    }

    drawingVertices.value = [...verts, { x: pos.x, y: pos.y }];
  }

  function finishFreeform(): void {
    const verts = drawingVertices.value;
    if (verts.length >= 3) {
      live.pushEvent("create_zone", { vertices: verts });
    }
    drawingVertices.value = [];
    cursorPos.value = null;
  }

  function cancelFreeform(): void {
    drawingVertices.value = [];
    cursorPos.value = null;
  }

  // Track cursor for preview line
  function onStageMouseMove(_e: KonvaEventObject<MouseEvent>): void {
    if (!isDrawing.value) {
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
    cursorPos.value = {
      x: (pointer.x - stageConfig.x) / stageConfig.scaleX,
      y: (pointer.y - stageConfig.y) / stageConfig.scaleY,
    };
  }

  // Double-click finishes freeform (with 3+ vertices)
  function onStageDblClick(_e: KonvaEventObject<MouseEvent>): void {
    if (!isDrawing.value) {
      return;
    }
    if (drawingVertices.value.length >= 3) {
      finishFreeform();
    }
  }

  // Escape cancels freeform drawing
  function onKeyDown(e: KeyboardEvent): void {
    if (e.key === "Escape" && isDrawing.value) {
      e.preventDefault();
      cancelFreeform();
    }
  }

  onMounted(() => {
    window.addEventListener("keydown", onKeyDown);
  });

  onUnmounted(() => {
    window.removeEventListener("keydown", onKeyDown);
  });

  // Computed Konva configs for the drawing overlay layer
  const drawingOverlay = computed<DrawingOverlay | null>(() => {
    const verts = drawingVertices.value;
    if (verts.length === 0) {
      return null;
    }

    const pixelVerts = verts.map((v) => percentToPixel(v.x, v.y));

    // Flat points for ghost polygon
    const ghostPoints: number[] = [];
    for (const p of pixelVerts) {
      ghostPoints.push(p.x, p.y);
    }

    // Preview line from last vertex to cursor
    let previewLine: number[] | null = null;
    if (cursorPos.value && pixelVerts.length > 0) {
      const last = pixelVerts[pixelVerts.length - 1];
      previewLine = [last.x, last.y, cursorPos.value.x, cursorPos.value.y];
    }

    // Close-to-first indicator line
    let closeLine: number[] | null = null;
    if (cursorPos.value && pixelVerts.length >= 3) {
      const first = pixelVerts[0];
      const dx = cursorPos.value.x - first.x;
      const dy = cursorPos.value.y - first.y;
      if (Math.sqrt(dx * dx + dy * dy) < CLOSE_THRESHOLD_PX) {
        const last = pixelVerts[pixelVerts.length - 1];
        closeLine = [last.x, last.y, first.x, first.y];
      }
    }

    // Vertex markers
    const vertexConfigs: VertexConfig[] = pixelVerts.map((p, i) => ({
      x: p.x,
      y: p.y,
      radius: VERTEX_RADIUS,
      fill: i === 0 && verts.length >= 3 ? "#ffffff" : VERTEX_FILL,
      stroke: GHOST_STROKE,
      strokeWidth: i === 0 && verts.length >= 3 ? 2 : 0,
      listening: false,
    }));

    return {
      ghostPoints,
      previewLine,
      closeLine,
      vertexConfigs,
    };
  });

  return {
    isDrawing,
    drawingOverlay,
    handleZoneCreationClick,
    onStageMouseMove,
    onStageDblClick,
    cancelFreeform,
  };
}
