<script setup>
import { computed, ref, toRef } from "vue";
import { useAnnotationEditing } from "../composables/useAnnotationEditing";
import { useAnnotations } from "../composables/useAnnotations";
import { useCanvasCreation } from "../composables/useCanvasCreation";
import { useConnectionDrawing } from "../composables/useConnectionDrawing";
import { useConnections } from "../composables/useConnections";
import { useDrag } from "../composables/useDrag";
import { useKonvaStage } from "../composables/useKonvaStage";
import { usePins } from "../composables/usePins";
import { useSelection } from "../composables/useSelection";
import { useVertexEditor } from "../composables/useVertexEditor";
import { useWaypointEditor } from "../composables/useWaypointEditor";
import { useZoneDrag } from "../composables/useZoneDrag";
import { useZoneDrawing } from "../composables/useZoneDrawing";
import { useZones } from "../composables/useZones";
import SceneFloatingToolbar from "./SceneFloatingToolbar.vue";

const props = defineProps({
	sceneData: { type: Object, default: null },
	pins: { type: Array, default: () => [] },
	zones: { type: Array, default: () => [] },
	connections: { type: Array, default: () => [] },
	annotations: { type: Array, default: () => [] },
	layers: { type: Array, default: () => [] },
	activeTool: { type: String, default: "select" },
	editMode: { type: Boolean, default: true },
	canEdit: { type: Boolean, default: false },
	currentUserId: { type: [Number, String], default: 0 },
	entityLocks: { type: Object, default: () => ({}) },
});

const containerRef = ref(null);
const activeToolRef = toRef(props, "activeTool");

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
	stagePointerToWorld,
} = useKonvaStage({
	containerRef,
	sceneData: toRef(props, "sceneData"),
	activeTool: activeToolRef,
	editMode: toRef(props, "editMode"),
});

const editRefs = {
	editMode: toRef(props, "editMode"),
	canEdit: toRef(props, "canEdit"),
};

const { handleCreationClick } = useCanvasCreation({
	stageRef,
	stageConfig,
	pixelToPercent,
	activeTool: activeToolRef,
	...editRefs,
});

const {
	isDrawing: isDrawingZone,
	drawingOverlay,
	handleZoneCreationClick,
	onStageMouseMove,
	onStageDblClick,
} = useZoneDrawing({
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
	isDrawingConnection,
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
	pins: toRef(props, "pins"),
});

// Unified creation click: try pin/annotation first, then zone, then connection cancel
function onCreationClick(e) {
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

const { isDragging, dragOverrides, onDragStart, onDragMove, onDragEnd } =
	useDrag({
		pixelToPercent,
	});

const {
	isDraggingZone,
	zoneDragOverride,
	onZoneMouseDown,
	onZoneDragMove,
	onZoneDragEnd,
} = useZoneDrag({
	stageRef,
	stageConfig,
	pixelToPercent,
	zones: toRef(props, "zones"),
	selectedType,
	selectedId,
	...editRefs,
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
});

const { pinConfigs } = usePins({
	pins: toRef(props, "pins"),
	layers: toRef(props, "layers"),
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
	percentToPixel,
	activeTool: activeToolRef,
	...selectionRefs,
	...editRefs,
});

const {
	editingZoneId,
	editingVertices,
	isEditing: isEditingVertices,
	startEditing: startVertexEditing,
	stopEditing: stopVertexEditing,
	onVertexDragMove,
	onVertexDragEnd,
	onVertexClick,
	insertVertex,
	vertexEditorConfigs,
} = useVertexEditor({
	stageConfig,
	pixelToPercent,
	percentToPixel,
	zones: toRef(props, "zones"),
	selectedType,
	selectedId,
});

const { zoneConfigs } = useZones({
	zones: toRef(props, "zones"),
	layers: toRef(props, "layers"),
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
	percentToPixel,
	...selectionRefs,
	zoneDragOverride,
	editingZoneId,
	editingVertices,
});

const { annotationConfigs } = useAnnotations({
	annotations: toRef(props, "annotations"),
	layers: toRef(props, "layers"),
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
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
	connections: toRef(props, "connections"),
	pins: toRef(props, "pins"),
	layers: toRef(props, "layers"),
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
	stopEditing: stopWaypointEditing,
	onWaypointDragMove,
	onWaypointDragEnd,
	onWaypointClick,
	insertWaypoint,
	waypointEditorConfigs,
} = useWaypointEditor({
	connections: toRef(props, "connections"),
	pins: toRef(props, "pins"),
	pixelToPercent,
	percentToPixel,
	...selectionRefs,
});

const { startEditing, isEditingAnnotation, getDisplayText } =
	useAnnotationEditing({
		containerRef,
		stageConfig,
	});

function handleAnnotationDblClick(annConfig, e) {
	if (!props.canEdit || !props.editMode) return;
	if (e) e.cancelBubble = true;
	startEditing(annConfig);
}

function handleConnectionDblClick(connectionId, e) {
	if (!props.canEdit || !props.editMode) return;
	if (e) e.cancelBubble = true;
	startWaypointEditing(connectionId);
}

function handleZoneDblClick(zoneId, e) {
	if (!props.canEdit || !props.editMode) return;
	if (e) e.cancelBubble = true;
	startVertexEditing(zoneId);
}

function handlePinClick(pinId, e) {
	if (handlePinClickForConnection(pinId, e)) return;
	handleElementClick("pin", pinId, e);
}

function handleStageMouseMove(e) {
	if (isDragging.value) return;
	onStageMouseMove(e);
	onConnectionMouseMove();
	onZoneDragMove();
}

// Compute selected element position for toolbar positioning
const selectedElementPosition = computed(() => {
	if (!selectedType.value || !selectedId.value) return null;

	if (selectedType.value === "annotation") {
		const ann = annotationConfigs.value.find((a) => a.id === selectedId.value);
		if (ann)
			return { x: ann.x, y: ann.y, width: ann.width, height: ann.height };
	}
	if (selectedType.value === "pin") {
		const pin = pinConfigs.value.find((p) => p.id === selectedId.value);
		if (pin)
			return {
				x: pin.x - pin.radius,
				y: pin.y - pin.radius,
				width: pin.diameter,
				height: pin.diameter,
			};
	}
	if (selectedType.value === "zone") {
		const zone = zoneConfigs.value.find((z) => z.id === selectedId.value);
		if (zone && zone.points.length >= 4) {
			const xs = [];
			const ys = [];
			for (let i = 0; i < zone.points.length; i += 2) {
				xs.push(zone.points[i]);
				ys.push(zone.points[i + 1]);
			}
			const minX = Math.min(...xs);
			const minY = Math.min(...ys);
			return {
				x: minX,
				y: minY,
				width: Math.max(...xs) - minX,
				height: Math.max(...ys) - minY,
			};
		}
	}
	if (selectedType.value === "connection") {
		const conn = connectionConfigs.value.find((c) => c.id === selectedId.value);
		if (conn && conn.points.length >= 4) {
			const midIdx = Math.floor(conn.points.length / 2);
			const midX = (conn.points[midIdx - 2] + conn.points[midIdx]) / 2;
			const midY = (conn.points[midIdx - 1] + conn.points[midIdx + 1]) / 2;
			return { x: midX, y: midY, width: 0, height: 0 };
		}
	}
	return null;
});

function clipCircle(radius) {
	return (ctx) => {
		ctx.arc(0, 0, radius, 0, Math.PI * 2);
	};
}

const LABEL_COLOR = "#d1d5db";
</script>

<template>
  <div ref="containerRef" class="w-full h-full relative" :style="{ cursor: cursorStyle }">
    <v-stage ref="stageRef" :config="stageConfig" @wheel="handleWheel" @click="handleStageClick" @mousemove="handleStageMouseMove" @mouseup="onZoneDragEnd" @dblclick="onStageDblClick">
      <!-- Background layer (static, no hit detection needed) -->
      <v-layer :config="{ listening: false }">
        <v-image v-if="backgroundConfig" :config="backgroundConfig" />
        <template v-else>
          <v-rect :config="gridRectConfig" />
          <v-line v-for="(line, i) in gridLines" :key="'grid-' + i" :config="line" />
        </template>
      </v-layer>

      <!-- Zones + Connections layer (non-draggable interactive elements) -->
      <v-layer>
        <v-group
          v-for="zone in zoneConfigs"
          :key="'zone-' + zone.id"
          :config="{ listening: zone.listening }"
          @click="(e) => handleElementClick('zone', zone.id, e)"
          @dblclick="(e) => handleZoneDblClick(zone.id, e)"
          @mousedown="(e) => onZoneMouseDown(zone.id, e)"
        >
          <!-- Zone polygon -->
          <v-line
            :config="{
              points: zone.points,
              fill: zone.fill,
              stroke: zone.stroke,
              strokeWidth: zone.strokeWidth,
              dash: zone.dash,
              opacity: zone.opacity,
              closed: true,
              hitStrokeWidth: zone.hitStrokeWidth,
              shadowColor: zone.isSelected ? SELECTION_COLOR : undefined,
              shadowBlur: zone.isSelected ? 10 : 0,
              shadowOpacity: zone.isSelected ? 0.8 : 0,
              shadowEnabled: zone.isSelected,
              shadowForStrokeEnabled: false,
              perfectDrawEnabled: false,
            }"
          />
          <v-text
            v-if="zone.name"
            :config="{
              text: zone.name,
              fill: LABEL_COLOR,
              fontSize: 12,
              fontStyle: '600',
              align: 'center',
              x: zone.centroidX - 50,
              y: zone.centroidY - 8,
              width: 100,
              ellipsis: true,
              wrap: 'none',
              shadowColor: 'black',
              shadowBlur: 3,
              shadowOpacity: 0.8,
              shadowForStrokeEnabled: false,
              listening: false,
            }"
          />
          <v-image
            v-if="zone.lockBadge"
            :config="{
              image: zone.lockBadge,
              x: zone.lockBadgeX,
              y: zone.lockBadgeY,
              width: 14,
              height: 14,
              listening: false,
            }"
          />
        </v-group>
        <v-group
          v-for="conn in connectionConfigs"
          :key="'conn-' + conn.id"
          :config="{ listening: conn.listening }"
          @click="(e) => handleElementClick('connection', conn.id, e)"
          @dblclick="(e) => handleConnectionDblClick(conn.id, e)"
        >
          <v-arrow
            :config="{
              points: conn.points,
              stroke: conn.stroke,
              fill: conn.fill,
              strokeWidth: conn.strokeWidth,
              dash: conn.dash,
              opacity: conn.opacity,
              pointerLength: conn.pointerLength,
              pointerWidth: conn.pointerWidth,
              pointerAtBeginning: conn.pointerAtBeginning,
              pointerAtEnding: conn.pointerAtEnding,
              hitStrokeWidth: conn.hitStrokeWidth,
            }"
          />
          <v-text v-if="conn.labelConfig" :config="conn.labelConfig" />
        </v-group>
      </v-layer>

      <!-- Pin layer (draggable) -->
      <v-layer>
        <v-group
          v-for="pin in pinConfigs"
          :key="'pin-' + pin.id"
          :config="{ x: pin.x, y: pin.y, listening: pin.listening, draggable: pin.draggable }"
          @click="(e) => handlePinClick(pin.id, e)"
          @dragstart="(e) => onDragStart('pin', pin.id, e)"
          @dragmove="(e) => onDragMove('pin', pin.id, e)"
          @dragend="(e) => onDragEnd('pin', pin.id, e)"
        >
          <v-circle
            v-if="pin.isSelected"
            :config="{
              radius: pin.radius + 5,
              stroke: SELECTION_COLOR,
              strokeWidth: 3,
              listening: false,
            }"
          />
          <!-- Connection drawing: source highlight -->
          <v-circle
            v-if="sourcePinId === pin.id"
            :config="{
              radius: pin.radius + 6,
              stroke: SOURCE_HIGHLIGHT_COLOR,
              strokeWidth: 2,
              dash: [6, 3],
              listening: false,
            }"
          />
          <!-- Connection drawing: target hover highlight -->
          <v-circle
            v-if="hoveredPinId === pin.id"
            :config="{
              radius: pin.radius + 6,
              stroke: TARGET_HIGHLIGHT_COLOR,
              strokeWidth: 2,
              listening: false,
            }"
          />
          <v-image
            v-if="pin.iconCanvas"
            :config="{
              image: pin.iconCanvas,
              x: -pin.iconCanvas.width / 2,
              y: -pin.iconCanvas.height / 2,
              width: pin.iconCanvas.width,
              height: pin.iconCanvas.height,
            }"
          />
          <v-image
            v-else-if="pin.initialsCanvas"
            :config="{
              image: pin.initialsCanvas,
              x: -pin.initialsCanvas.width / 2,
              y: -pin.initialsCanvas.height / 2,
              width: pin.initialsCanvas.width,
              height: pin.initialsCanvas.height,
            }"
          />
          <template v-else-if="pin.image">
            <v-circle
              :config="{
                radius: pin.radius,
                fill: pin.color,
                opacity: pin.opacity,
                shadowColor: 'black',
                shadowBlur: 6,
                shadowOpacity: 0.3,
                shadowOffsetY: 2,
                shadowForStrokeEnabled: false,
                perfectDrawEnabled: false,
              }"
            />
            <v-group :config="{ clipFunc: clipCircle(pin.radius) }">
              <v-image
                :config="{
                  image: pin.image,
                  x: -pin.radius,
                  y: -pin.radius,
                  width: pin.diameter,
                  height: pin.diameter,
                }"
              />
            </v-group>
          </template>
          <v-text
            v-if="pin.label"
            :config="{
              text: pin.label,
              fill: LABEL_COLOR,
              fontSize: 11,
              fontStyle: '600',
              align: 'center',
              x: -50,
              y: pin.radius + 6,
              width: 100,
              ellipsis: true,
              wrap: 'none',
              listening: false,
            }"
          />
          <v-image
            v-if="pin.lockBadge"
            :config="{
              image: pin.lockBadge,
              x: pin.radius - 10,
              y: -pin.radius - 4,
              width: 14,
              height: 14,
              listening: false,
            }"
          />
        </v-group>
      </v-layer>

      <!-- Annotation layer (draggable) -->
      <v-layer>
        <v-group
          v-for="ann in annotationConfigs"
          :key="'ann-' + ann.id"
          :config="{ x: ann.x, y: ann.y, listening: ann.listening, draggable: ann.draggable }"
          @click="(e) => handleElementClick('annotation', ann.id, e)"
          @dblclick="(e) => handleAnnotationDblClick(ann, e)"
          @dragstart="(e) => onDragStart('annotation', ann.id, e)"
          @dragmove="(e) => onDragMove('annotation', ann.id, e)"
          @dragend="(e) => onDragEnd('annotation', ann.id, e)"
        >
          <v-rect
            v-if="ann.isSelected"
            :config="{
              x: -3,
              y: -3,
              width: ann.width + 6,
              height: ann.height + 6,
              stroke: SELECTION_COLOR,
              strokeWidth: 2,
              listening: false,
            }"
          />
          <v-line
            :config="{
              points: ann.bodyPoints,
              fill: ann.color,
              opacity: ann.bgOpacity,
              closed: true,
              perfectDrawEnabled: false,
            }"
          />
          <v-line
            :config="{
              points: ann.foldPoints,
              fill: ann.color,
              closed: true,
              listening: false,
              perfectDrawEnabled: false,
            }"
          />
          <v-text
            v-if="!isEditingAnnotation(ann.id)"
            :config="{
              text: getDisplayText(ann.id, ann.text),
              fill: '#111827',
              fontSize: ann.fontSize,
              fontStyle: '600',
              fontFamily: 'system-ui, sans-serif',
              lineHeight: 1.3,
              width: ann.textWidth,
              x: ann.padLeft,
              y: ann.padTop,
              wrap: 'word',
              listening: false,
            }"
          />
          <v-image
            v-if="ann.lockBadge"
            :config="{
              image: ann.lockBadge,
              x: ann.width - 18,
              y: -4,
              width: 14,
              height: 14,
              listening: false,
            }"
          />
        </v-group>
      </v-layer>

      <!-- Vertex editor layer (zone vertex editing on dblclick) -->
      <v-layer v-if="vertexEditorConfigs">
        <!-- Midpoint anchors (click to insert vertex) -->
        <v-circle
          v-for="(mp, i) in vertexEditorConfigs.midpointAnchors"
          :key="'mp-' + i"
          :config="{
            x: mp.x,
            y: mp.y,
            radius: mp.radius,
            fill: mp.fill,
            stroke: mp.stroke,
            strokeWidth: mp.strokeWidth,
          }"
          @click="(e) => insertVertex(mp.afterIndex, e)"
        />
        <!-- Vertex anchors (drag to reshape, ctrl+click to remove) -->
        <v-circle
          v-for="(va, i) in vertexEditorConfigs.vertexAnchors"
          :key="'va-' + i"
          :config="{
            x: va.x,
            y: va.y,
            radius: va.radius,
            fill: va.fill,
            stroke: va.stroke,
            strokeWidth: va.strokeWidth,
            draggable: true,
          }"
          @dragmove="(e) => onVertexDragMove(va.index, e)"
          @dragend="onVertexDragEnd"
          @click="(e) => onVertexClick(va.index, e)"
        />
      </v-layer>

      <!-- Waypoint editor layer (connection waypoint editing on dblclick) -->
      <v-layer v-if="waypointEditorConfigs">
        <!-- Midpoint anchors (click to insert waypoint) -->
        <v-circle
          v-for="(mp, i) in waypointEditorConfigs.midpointAnchors"
          :key="'wmp-' + i"
          :config="{
            x: mp.x,
            y: mp.y,
            radius: mp.radius,
            fill: mp.fill,
            stroke: mp.stroke,
            strokeWidth: mp.strokeWidth,
          }"
          @click="(e) => insertWaypoint(mp.segmentIndex, e)"
        />
        <!-- Waypoint anchors (drag to reshape, ctrl+click to remove) -->
        <v-circle
          v-for="(wa, i) in waypointEditorConfigs.waypointAnchors"
          :key="'wa-' + i"
          :config="{
            x: wa.x,
            y: wa.y,
            radius: wa.radius,
            fill: wa.fill,
            stroke: wa.stroke,
            strokeWidth: wa.strokeWidth,
            draggable: true,
          }"
          @dragmove="(e) => onWaypointDragMove(wa.index, e)"
          @dragend="onWaypointDragEnd"
          @click="(e) => onWaypointClick(wa.index, e)"
        />
      </v-layer>

      <!-- Connection drawing preview line -->
      <v-layer v-if="connectionPreviewLine" :config="{ listening: false }">
        <v-line
          :config="{
            points: connectionPreviewLine,
            stroke: PREVIEW_STROKE,
            strokeWidth: 2,
            dash: [8, 4],
            listening: false,
          }"
        />
      </v-layer>

      <!-- Drawing overlay layer (freeform zone creation) -->
      <v-layer v-if="drawingOverlay" :config="{ listening: false }">
        <v-line
          :config="{
            points: drawingOverlay.ghostPoints,
            fill: 'rgba(99,102,241,0.15)',
            stroke: '#6366f1',
            strokeWidth: 2,
            dash: [6, 4],
            closed: drawingOverlay.ghostPoints.length >= 6,
            listening: false,
          }"
        />
        <v-line
          v-if="drawingOverlay.previewLine"
          :config="{
            points: drawingOverlay.previewLine,
            stroke: '#6366f1',
            strokeWidth: 1,
            dash: [4, 4],
            listening: false,
          }"
        />
        <v-line
          v-if="drawingOverlay.closeLine"
          :config="{
            points: drawingOverlay.closeLine,
            stroke: '#22c55e',
            strokeWidth: 2,
            listening: false,
          }"
        />
        <v-circle
          v-for="(vc, i) in drawingOverlay.vertexConfigs"
          :key="'dv-' + i"
          :config="vc"
        />
      </v-layer>
    </v-stage>

    <!-- Floating toolbar (HTML overlay above canvas) -->
    <SceneFloatingToolbar
      :selected-type="selectedType"
      :selected-id="selectedId"
      :annotations="annotations"
      :connections="connections"
      :pins="pins"
      :zones="zones"
      :layers="layers"
      :can-edit="canEdit"
      :edit-mode="editMode"
      :stage-config="stageConfig"
      :element-position="selectedElementPosition"
      :container-width="stageConfig.width"
      :is-dragging="isDragging || isDraggingZone || isEditingWaypoints"
    />
  </div>
</template>
