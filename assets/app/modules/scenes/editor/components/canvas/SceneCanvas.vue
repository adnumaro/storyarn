<script setup lang="ts">
import type { KonvaEventObject } from "konva/lib/Node";
import { computed, ref, toRef } from "vue";
import { useAnnotationEditing } from "../../composables/useAnnotationEditing";
import { useAnnotations, type AnnotationConfig } from "../../composables/useAnnotations";
import { useCanvasCreation } from "../../composables/useCanvasCreation";
import { useConnectionDrawing } from "../../composables/useConnectionDrawing";
import { useConnections } from "../../../canvas/composables/useConnections";
import { useDrag } from "../../composables/useDrag";
import { useKonvaStage } from "../../../canvas/composables/useKonvaStage";
import { usePins } from "../../../canvas/composables/usePins";
import { useSelection } from "../../composables/useSelection";
import { useVertexEditor } from "../../composables/useVertexEditor";
import { useWaypointEditor } from "../../composables/useWaypointEditor";
import { useZoneDrag } from "../../composables/useZoneDrag";
import { useZoneDrawing } from "../../composables/useZoneDrawing";
import { useZones } from "../../../canvas/composables/useZones";
import AnnotationLayer from "./layers/AnnotationLayer.vue";
import BackgroundLayer from "./layers/BackgroundLayer.vue";
import ConnectionPreviewLayer from "./layers/ConnectionPreviewLayer.vue";
import DrawingOverlayLayer from "./layers/DrawingOverlayLayer.vue";
import PinLayer from "./layers/PinLayer.vue";
import VertexEditorLayer from "./layers/VertexEditorLayer.vue";
import WaypointEditorLayer from "./layers/WaypointEditorLayer.vue";
import ZoneConnectionLayer from "./layers/ZoneConnectionLayer.vue";
import SceneFloatingToolbar from "../toolbar/SceneFloatingToolbar.vue";

interface SceneDataProps {
  width: number;
  height: number;
  backgroundUrl: string | null;
  gridEnabled: boolean;
}

interface PinData {
  id: number | string;
  positionX: number;
  positionY: number;
  size: string | null;
  color: string | null;
  opacity: number | null;
  pinType: string;
  label: string | null;
  locked: boolean;
  layerId: number | string | null;
  hidden: boolean;
  iconAssetUrl: string | null;
  sheetAvatarUrl: string | null;
  sheetId: number | string | null;
  position: number | null;
}

interface ZoneData {
  id: number | string;
  name: string;
  vertices: { x: number; y: number }[] | null;
  fillColor: string | null;
  borderColor: string | null;
  borderWidth: number | null;
  borderStyle: string | null;
  opacity: number | null;
  position: number | null;
  layerId: number | string | null;
  locked: boolean;
}

interface ConnectionData {
  id: number | string;
  fromPinId: number | string;
  toPinId: number | string;
  waypoints: { x: number; y: number }[] | null;
  color: string | null;
  lineWidth: number | null;
  lineStyle: string | null;
  label: string | null;
  showLabel: boolean;
  bidirectional: boolean;
}

interface AnnotationData {
  id: number | string;
  positionX: number;
  positionY: number;
  text: string | null;
  color: string | null;
  fontSize: string;
  position: number | null;
  layerId: number | string | null;
  locked: boolean;
}

interface LayerData {
  id: number | string;
  visible: boolean;
  name: string;
}

interface EntityLock {
  userId: number | string;
}

interface CollaborationData {
  userId: number | string;
  locks: Record<string, EntityLock>;
}

const {
  sceneData = null,
  pins = [],
  zones = [],
  connections = [],
  annotations = [],
  layers = [],
  activeTool = "select",
  editMode = true,
  canEdit = false,
  collaboration = { userId: 0, locks: {} },
} = defineProps<{
  sceneData: SceneDataProps | null;
  pins: PinData[];
  zones: ZoneData[];
  connections: ConnectionData[];
  annotations: AnnotationData[];
  layers: LayerData[];
  activeTool: string;
  editMode: boolean;
  canEdit: boolean;
  collaboration: CollaborationData;
}>();

const containerRef = ref<HTMLDivElement | null>(null);
const activeToolRef = toRef(() => activeTool);

const {
  stageConfig,
  stageRef,
  backgroundConfig,
  gridRectConfig,
  gridLines,
  cursorStyle,
  handleWheel,
  percentToPixel,
  pixelToPercent,
} = useKonvaStage({
  containerRef,
  sceneData: toRef(() => sceneData),
  activeTool: activeToolRef,
  editMode: toRef(() => editMode),
});

const editRefs = {
  editMode: toRef(() => editMode),
  canEdit: toRef(() => canEdit),
};

const { handleCreationClick } = useCanvasCreation({
  stageRef,
  stageConfig,
  pixelToPercent,
  activeTool: activeToolRef,
  ...editRefs,
});

const { drawingOverlay, handleZoneCreationClick, onStageMouseMove, onStageDblClick } =
  useZoneDrawing({
    stageRef,
    stageConfig,
    pixelToPercent,
    percentToPixel,
    activeTool: activeToolRef,
    ...editRefs,
  });

const {
  sourcePinId,
  hoveredPinId,
  handlePinClickForConnection,
  handleStageClickForConnection,
  onMouseMove: onConnectionMouseMove,
  previewLine: connectionPreviewLine,
  SOURCE_HIGHLIGHT_COLOR,
  TARGET_HIGHLIGHT_COLOR,
  PREVIEW_STROKE,
} = useConnectionDrawing({
  stageRef,
  stageConfig,
  percentToPixel,
  activeTool: activeToolRef,
  ...editRefs,
  pins: toRef(() => pins),
});

// Unified creation click: try pin/annotation first, then zone, then connection cancel
function onCreationClick(e: KonvaEventObject<MouseEvent>): boolean {
  if (handleCreationClick(e)) return true;
  if (handleZoneCreationClick(e)) return true;
  if (handleStageClickForConnection(e)) return true;
  return false;
}

const {
  selectedType,
  selectedId,
  isSelectMode,
  handleElementClick,
  handleStageClick,
  SELECTION_COLOR,
} = useSelection({ activeTool: activeToolRef, onCreationClick });

const selectionRefs = { selectedType, selectedId, isSelectMode };

const { isDragging, dragOverrides, onDragStart, onDragMove, onDragEnd } = useDrag({
  pixelToPercent,
});

const { isDraggingZone, zoneDragOverride, onZoneMouseDown, onZoneDragMove, onZoneDragEnd } =
  useZoneDrag({
    stageRef,
    stageConfig,
    pixelToPercent,
    zones: toRef(() => zones),
    selectedType,
    selectedId,
    ...editRefs,
    entityLocks: toRef(() => collaboration.locks),
    currentUserId: toRef(() => collaboration.userId),
  });

const { pinConfigs } = usePins({
  pins: toRef(() => pins),
  layers: toRef(() => layers),
  entityLocks: toRef(() => collaboration.locks),
  currentUserId: toRef(() => collaboration.userId),
  percentToPixel,
  activeTool: activeToolRef,
  ...selectionRefs,
  ...editRefs,
});

const {
  editingZoneId,
  editingVertices,
  startEditing: startVertexEditing,
  onVertexDragMove,
  onVertexDragEnd,
  onVertexClick,
  insertVertex,
  vertexEditorConfigs,
} = useVertexEditor({
  stageConfig,
  pixelToPercent,
  percentToPixel,
  zones: toRef(() => zones),
  selectedType,
  selectedId,
});

const { zoneConfigs } = useZones({
  zones: toRef(() => zones),
  layers: toRef(() => layers),
  entityLocks: toRef(() => collaboration.locks),
  currentUserId: toRef(() => collaboration.userId),
  percentToPixel,
  ...selectionRefs,
  zoneDragOverride,
  editingZoneId,
  editingVertices,
});

const { annotationConfigs } = useAnnotations({
  annotations: toRef(() => annotations),
  layers: toRef(() => layers),
  entityLocks: toRef(() => collaboration.locks),
  currentUserId: toRef(() => collaboration.userId),
  percentToPixel,
  ...selectionRefs,
  ...editRefs,
});

// Waypoint edit override for live connection path preview during editing
const waypointEditOverride = computed(() => {
  if (!editingWaypointConnectionId.value) return null;
  return {
    connectionId: editingWaypointConnectionId.value,
    waypoints: editingWaypoints.value,
  };
});

const { connectionConfigs } = useConnections({
  connections: toRef(() => connections),
  pins: toRef(() => pins),
  layers: toRef(() => layers),
  percentToPixel,
  ...selectionRefs,
  dragOverrides,
  waypointEditOverride,
});

const {
  editingConnectionId: editingWaypointConnectionId,
  editingWaypoints,
  isEditing: isEditingWaypoints,
  startEditing: startWaypointEditing,
  onWaypointDragMove,
  onWaypointDragEnd,
  onWaypointClick,
  insertWaypoint,
  waypointEditorConfigs,
} = useWaypointEditor({
  connections: toRef(() => connections),
  pins: toRef(() => pins),
  pixelToPercent,
  percentToPixel,
  ...selectionRefs,
});

const { startEditing, isEditingAnnotation, getDisplayText } = useAnnotationEditing({
  containerRef,
  stageConfig,
});

function handleAnnotationDblClick(
  annConfig: AnnotationConfig,
  e: KonvaEventObject<MouseEvent>,
): void {
  if (!canEdit || !editMode) return;
  if (e) e.cancelBubble = true;
  startEditing(annConfig);
}

function handleConnectionDblClick(
  connectionId: number | string,
  e: KonvaEventObject<MouseEvent>,
): void {
  if (!canEdit || !editMode) return;
  if (e) e.cancelBubble = true;
  startWaypointEditing(connectionId);
}

function handleZoneDblClick(zoneId: number | string, e: KonvaEventObject<MouseEvent>): void {
  if (!canEdit || !editMode) return;
  if (e) e.cancelBubble = true;
  startVertexEditing(zoneId);
}

function handlePinClick(pinId: number | string, e: KonvaEventObject<MouseEvent>): void {
  if (handlePinClickForConnection(pinId, e)) return;
  handleElementClick("pin", pinId, e);
}

function handleStageMouseMove(e: KonvaEventObject<MouseEvent>): void {
  if (isDragging.value) return;
  onStageMouseMove(e);
  onConnectionMouseMove();
  onZoneDragMove();
}

interface ElementRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

function getAnnotationPosition(id: number | string): ElementRect | null {
  const ann = annotationConfigs.value.find((a) => a.id === id);
  return ann ? { x: ann.x, y: ann.y, width: ann.width, height: ann.height } : null;
}

function getPinPosition(id: number | string): ElementRect | null {
  const pin = pinConfigs.value.find((p) => p.id === id);
  return pin
    ? { x: pin.x - pin.radius, y: pin.y - pin.radius, width: pin.diameter, height: pin.diameter }
    : null;
}

function getZonePosition(id: number | string): ElementRect | null {
  const zone = zoneConfigs.value.find((z) => z.id === id);
  if (!zone || zone.points.length < 4) return null;
  const xs: number[] = [];
  const ys: number[] = [];
  for (let i = 0; i < zone.points.length; i += 2) {
    xs.push(zone.points[i]);
    ys.push(zone.points[i + 1]);
  }
  const minX = Math.min(...xs);
  const minY = Math.min(...ys);
  return { x: minX, y: minY, width: Math.max(...xs) - minX, height: Math.max(...ys) - minY };
}

function getConnectionPosition(id: number | string): ElementRect | null {
  const conn = connectionConfigs.value.find((c) => c.id === id);
  if (!conn || conn.points.length < 4) return null;
  const midIdx = Math.floor(conn.points.length / 2);
  const midX = (conn.points[midIdx - 2] + conn.points[midIdx]) / 2;
  const midY = (conn.points[midIdx - 1] + conn.points[midIdx + 1]) / 2;
  return { x: midX, y: midY, width: 0, height: 0 };
}

const POSITION_GETTERS: Record<string, (id: number | string) => ElementRect | null> = {
  annotation: getAnnotationPosition,
  pin: getPinPosition,
  zone: getZonePosition,
  connection: getConnectionPosition,
};

// Compute selected element position for toolbar positioning
const selectedElementPosition = computed(() => {
  if (!selectedType.value || !selectedId.value) return null;
  const getter = POSITION_GETTERS[selectedType.value];
  return getter ? getter(selectedId.value) : null;
});

const ELEMENT_LISTS: Record<string, () => { id: number | string }[]> = {
  annotation: () => annotations,
  connection: () => connections,
  pin: () => pins,
  zone: () => zones,
};

const selectedElement = computed(() => {
  if (!selectedType.value) return null;
  const getter = ELEMENT_LISTS[selectedType.value];
  if (!getter) return null;
  return getter().find((e: { id: number | string }) => e.id === selectedId.value) || null;
});

function clipCircle(radius: number): (ctx: CanvasRenderingContext2D) => void {
  return (ctx: CanvasRenderingContext2D) => {
    ctx.arc(0, 0, radius, 0, Math.PI * 2);
  };
}

const LABEL_COLOR = "#d1d5db";
</script>

<template>
  <div ref="containerRef" class="w-full h-full relative" :style="{ cursor: cursorStyle }">
    <v-stage
      ref="stageRef"
      :config="stageConfig"
      @wheel="handleWheel"
      @click="handleStageClick"
      @mousemove="handleStageMouseMove"
      @mouseup="onZoneDragEnd"
      @dblclick="onStageDblClick"
    >
      <!-- Background layer (static, no hit detection needed) -->
      <BackgroundLayer
        :background-config="backgroundConfig"
        :grid-rect-config="gridRectConfig"
        :grid-lines="gridLines"
      />

      <!-- Zones + Connections layer (non-draggable interactive elements) -->
      <ZoneConnectionLayer
        :zone-configs="zoneConfigs"
        :connection-configs="connectionConfigs"
        :selection-color="SELECTION_COLOR"
        :label-color="LABEL_COLOR"
        @zone-click="(id, e) => handleElementClick('zone', id, e)"
        @zone-dblclick="handleZoneDblClick"
        @zone-mousedown="onZoneMouseDown"
        @connection-click="(id, e) => handleElementClick('connection', id, e)"
        @connection-dblclick="handleConnectionDblClick"
      />

      <!-- Pin layer (draggable) -->
      <PinLayer
        :pin-configs="pinConfigs"
        :source-pin-id="sourcePinId"
        :hovered-pin-id="hoveredPinId"
        :selection-color="SELECTION_COLOR"
        :source-highlight-color="SOURCE_HIGHLIGHT_COLOR"
        :target-highlight-color="TARGET_HIGHLIGHT_COLOR"
        :label-color="LABEL_COLOR"
        :clip-circle="clipCircle"
        @pin-click="handlePinClick"
        @dragstart="onDragStart"
        @dragmove="onDragMove"
        @dragend="onDragEnd"
      />

      <!-- Annotation layer (draggable) -->
      <AnnotationLayer
        :annotation-configs="annotationConfigs"
        :selection-color="SELECTION_COLOR"
        :is-editing-annotation="isEditingAnnotation"
        :get-display-text="getDisplayText"
        @annotation-click="(id, e) => handleElementClick('annotation', id, e)"
        @annotation-dblclick="handleAnnotationDblClick"
        @dragstart="onDragStart"
        @dragmove="onDragMove"
        @dragend="onDragEnd"
      />

      <!-- Vertex editor layer (zone vertex editing on dblclick) -->
      <VertexEditorLayer
        :vertex-editor-configs="vertexEditorConfigs"
        @insert-vertex="insertVertex"
        @vertex-dragmove="onVertexDragMove"
        @vertex-dragend="onVertexDragEnd"
        @vertex-click="onVertexClick"
      />

      <!-- Waypoint editor layer (connection waypoint editing on dblclick) -->
      <WaypointEditorLayer
        :waypoint-editor-configs="waypointEditorConfigs"
        @insert-waypoint="insertWaypoint"
        @waypoint-dragmove="onWaypointDragMove"
        @waypoint-dragend="onWaypointDragEnd"
        @waypoint-click="onWaypointClick"
      />

      <!-- Connection drawing preview line -->
      <ConnectionPreviewLayer
        :connection-preview-line="connectionPreviewLine"
        :preview-stroke="PREVIEW_STROKE"
      />

      <!-- Drawing overlay layer (freeform zone creation) -->
      <DrawingOverlayLayer :drawing-overlay="drawingOverlay" />
    </v-stage>

    <!-- Floating toolbar (HTML overlay above canvas) -->
    <SceneFloatingToolbar
      :selected-type="selectedType"
      :selected-element="selectedElement"
      :layers="layers"
      :can-edit="canEdit"
      :edit-mode="editMode"
      :stage-config="stageConfig"
      :element-position="selectedElementPosition"
      :is-dragging="isDragging || isDraggingZone || isEditingWaypoints"
    />
  </div>
</template>
