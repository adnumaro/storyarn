import { computed, onMounted, onUnmounted, ref, watch, type Ref } from "vue";
import { useLive } from "@composables/useLive";
import type { KonvaEventObject } from "konva/lib/Node";

const VERTEX_RADIUS = 6;
const MIDPOINT_RADIUS = 4;
const VERTEX_FILL = "#ffffff";
const VERTEX_STROKE = "#6366f1";
const MIDPOINT_FILL = "#e2e8f0";
const MIDPOINT_STROKE = "#94a3b8";
const MIN_VERTICES = 3;

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
}

interface VertexAnchorConfig {
  x: number;
  y: number;
  radius: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
  draggable: boolean;
  index: number;
}

interface MidpointAnchorConfig {
  x: number;
  y: number;
  radius: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
  afterIndex: number;
}

interface VertexEditorConfigs {
  vertexAnchors: VertexAnchorConfig[];
  midpointAnchors: MidpointAnchorConfig[];
}

interface StageConfig {
  scaleX: number;
  scaleY: number;
  x: number;
  y: number;
}

interface UseVertexEditorOpts {
  stageConfig: StageConfig;
  pixelToPercent: (pixelX: number, pixelY: number) => PixelPoint;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  zones: Ref<ZoneData[]>;
  selectedType: Ref<string | null>;
  selectedId: Ref<number | string | null>;
}

/**
 * Composable for editing zone polygon vertices via draggable anchor points.
 *
 * Activated by double-clicking a zone. Shows vertex handles (drag to reshape)
 * and midpoint handles (click to insert new vertex). Ctrl+click removes a vertex.
 * Deactivates on Escape, clicking empty canvas, or selecting another element.
 */
export function useVertexEditor({
  stageConfig: _stageConfig,
  pixelToPercent,
  percentToPixel,
  zones,
  selectedType,
  selectedId,
}: UseVertexEditorOpts) {
  const live = useLive();

  // The zone ID currently being vertex-edited (null = inactive)
  const editingZoneId = ref<number | string | null>(null);
  // Local working copy of vertices (percent coords) -- edits happen here before persist
  const editingVertices = ref<Vertex[]>([]);

  const isEditing = computed(() => editingZoneId.value !== null);

  /**
   * Enter vertex editing mode for a zone.
   */
  function startEditing(zoneId: number | string): void {
    const zone = zones.value.find((z) => z.id === zoneId);
    if (!zone || !zone.vertices || zone.vertices.length < MIN_VERTICES) {
      return;
    }
    editingZoneId.value = zoneId;
    editingVertices.value = zone.vertices.map((v) => ({ x: v.x, y: v.y }));
  }

  /**
   * Exit vertex editing mode.
   */
  function stopEditing(): void {
    editingZoneId.value = null;
    editingVertices.value = [];
  }

  /**
   * Called on vertex anchor dragmove -- update local vertex in real time.
   */
  function onVertexDragMove(index: number, e: KonvaEventObject<DragEvent>): void {
    const node = e.target;
    const worldX = node.x();
    const worldY = node.y();
    const pos = pixelToPercent(worldX, worldY);

    const verts = [...editingVertices.value];
    verts[index] = { x: pos.x, y: pos.y };
    editingVertices.value = verts;
  }

  /**
   * Called on vertex anchor dragend -- persist to server.
   */
  function onVertexDragEnd(): void {
    persistVertices();
  }

  /**
   * Click on midpoint -- insert a new vertex after the given index.
   */
  function insertVertex(afterIndex: number, e?: KonvaEventObject<MouseEvent>): void {
    if (e) {
      e.cancelBubble = true;
    }
    const verts = [...editingVertices.value];
    const a = verts[afterIndex];
    const b = verts[(afterIndex + 1) % verts.length];
    const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
    verts.splice(afterIndex + 1, 0, mid);
    editingVertices.value = verts;
    persistVertices();
  }

  /**
   * Ctrl+click on vertex -- remove it (min 3 enforced).
   */
  function removeVertex(index: number, e?: KonvaEventObject<MouseEvent>): void {
    if (e) {
      e.cancelBubble = true;
    }
    if (editingVertices.value.length <= MIN_VERTICES) {
      return;
    }
    const verts = [...editingVertices.value];
    verts.splice(index, 1);
    editingVertices.value = verts;
    persistVertices();
  }

  /**
   * Handle click on a vertex anchor -- check for Ctrl+click to remove.
   */
  function onVertexClick(index: number, e: KonvaEventObject<MouseEvent>): void {
    if (e) {
      e.cancelBubble = true;
    }
    const nativeEvt = e.evt;
    if (nativeEvt.ctrlKey || nativeEvt.metaKey) {
      removeVertex(index, e);
    }
  }

  function persistVertices(): void {
    if (!editingZoneId.value) {
      return;
    }
    const vertices = editingVertices.value.map((v) => ({
      x: Math.round(v.x * 100) / 100,
      y: Math.round(v.y * 100) / 100,
    }));
    live.pushEvent("update_zone_vertices", {
      id: String(editingZoneId.value),
      vertices,
    });
  }

  // Stop editing when selection changes away from the edited zone
  watch([selectedType, selectedId], ([type, id]) => {
    if (!isEditing.value) {
      return;
    }
    if (type !== "zone" || id !== editingZoneId.value) {
      stopEditing();
    }
  });

  // Escape exits vertex editing
  function onKeyDown(e: KeyboardEvent): void {
    if (e.key === "Escape" && isEditing.value) {
      e.preventDefault();
      stopEditing();
    }
  }

  onMounted(() => window.addEventListener("keydown", onKeyDown));
  onUnmounted(() => window.removeEventListener("keydown", onKeyDown));

  // Computed Konva configs for vertex and midpoint anchors
  const vertexEditorConfigs = computed<VertexEditorConfigs | null>(() => {
    if (!isEditing.value) {
      return null;
    }

    const verts = editingVertices.value;
    const pixelVerts = verts.map((v) => percentToPixel(v.x, v.y));

    const vertexAnchors: VertexAnchorConfig[] = pixelVerts.map((p, i) => ({
      x: p.x,
      y: p.y,
      radius: VERTEX_RADIUS,
      fill: VERTEX_FILL,
      stroke: VERTEX_STROKE,
      strokeWidth: 2,
      draggable: true,
      index: i,
    }));

    const midpointAnchors: MidpointAnchorConfig[] = pixelVerts.map((p, i) => {
      const next = pixelVerts[(i + 1) % pixelVerts.length];
      return {
        x: (p.x + next.x) / 2,
        y: (p.y + next.y) / 2,
        radius: MIDPOINT_RADIUS,
        fill: MIDPOINT_FILL,
        stroke: MIDPOINT_STROKE,
        strokeWidth: 1,
        afterIndex: i,
      };
    });

    return { vertexAnchors, midpointAnchors };
  });

  return {
    editingZoneId,
    editingVertices,
    isEditing,
    startEditing,
    stopEditing,
    onVertexDragMove,
    onVertexDragEnd,
    onVertexClick,
    insertVertex,
    vertexEditorConfigs,
  };
}
