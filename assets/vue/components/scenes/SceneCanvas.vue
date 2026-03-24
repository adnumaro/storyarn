<script setup>
import { computed, ref, toRef } from "vue";
import { useAnnotationEditing } from "./composables/useAnnotationEditing";
import { useAnnotations } from "./composables/useAnnotations";
import { useConnections } from "./composables/useConnections";
import { useKonvaStage } from "./composables/useKonvaStage";
import { usePins } from "./composables/usePins";
import { useSelection } from "./composables/useSelection";
import { useZones } from "./composables/useZones";
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
} = useKonvaStage({
	containerRef,
	sceneData: toRef(props, "sceneData"),
	activeTool: activeToolRef,
	editMode: toRef(props, "editMode"),
});

const {
	selectedType,
	selectedId,
	isSelectMode,
	handleElementClick,
	handleStageClick,
	SELECTION_COLOR,
} = useSelection({ activeTool: activeToolRef });

const selectionRefs = { selectedType, selectedId, isSelectMode };

const { pinConfigs } = usePins({
	pins: toRef(props, "pins"),
	layers: toRef(props, "layers"),
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
	percentToPixel,
	...selectionRefs,
});

const { zoneConfigs } = useZones({
	zones: toRef(props, "zones"),
	layers: toRef(props, "layers"),
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
	percentToPixel,
	...selectionRefs,
});

const { annotationConfigs } = useAnnotations({
	annotations: toRef(props, "annotations"),
	layers: toRef(props, "layers"),
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
	percentToPixel,
	...selectionRefs,
});

const { connectionConfigs } = useConnections({
	connections: toRef(props, "connections"),
	pins: toRef(props, "pins"),
	layers: toRef(props, "layers"),
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
    <v-stage ref="stageRef" :config="stageConfig" @wheel="handleWheel" @click="handleStageClick">
      <!-- Background layer -->
      <v-layer>
        <v-image v-if="backgroundConfig" :config="backgroundConfig" />
        <template v-else>
          <v-rect :config="gridRectConfig" />
          <v-line v-for="(line, i) in gridLines" :key="'grid-' + i" :config="line" />
        </template>
      </v-layer>

      <!-- Zone layer -->
      <v-layer>
        <v-group
          v-for="zone in zoneConfigs"
          :key="'zone-' + zone.id"
          :config="{ listening: zone.listening }"
          @click="(e) => handleElementClick('zone', zone.id, e)"
        >
          <v-line
            :config="{
              points: zone.points,
              fill: zone.fill,
              stroke: zone.stroke,
              strokeWidth: zone.strokeWidth,
              dash: zone.dash,
              opacity: zone.opacity,
              closed: true,
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
      </v-layer>

      <!-- Connection layer -->
      <v-layer>
        <v-group
          v-for="conn in connectionConfigs"
          :key="'conn-' + conn.id"
          :config="{ listening: conn.listening }"
          @click="(e) => handleElementClick('connection', conn.id, e)"
        >
          <v-line
            :config="{
              points: conn.points,
              stroke: conn.stroke,
              strokeWidth: conn.strokeWidth,
              dash: conn.dash,
              opacity: conn.opacity,
              hitStrokeWidth: conn.hitStrokeWidth,
            }"
          />
          <v-line
            v-if="conn.forwardArrow"
            :config="{
              points: conn.forwardArrow,
              fill: conn.arrowFill,
              closed: true,
              opacity: conn.opacity,
              listening: false,
            }"
          />
          <v-line
            v-if="conn.reverseArrow"
            :config="{
              points: conn.reverseArrow,
              fill: conn.arrowFill,
              closed: true,
              opacity: conn.opacity,
              listening: false,
            }"
          />
          <v-text v-if="conn.labelConfig" :config="conn.labelConfig" />
        </v-group>
      </v-layer>

      <!-- Pin layer -->
      <v-layer>
        <v-group
          v-for="pin in pinConfigs"
          :key="'pin-' + pin.id"
          :config="{ x: pin.x, y: pin.y, listening: pin.listening }"
          @click="(e) => handleElementClick('pin', pin.id, e)"
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

      <!-- Annotation layer -->
      <v-layer>
        <v-group
          v-for="ann in annotationConfigs"
          :key="'ann-' + ann.id"
          :config="{ x: ann.x, y: ann.y, listening: ann.listening }"
          @click="(e) => handleElementClick('annotation', ann.id, e)"
          @dblclick="(e) => handleAnnotationDblClick(ann, e)"
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
            }"
          />
          <v-line
            :config="{
              points: ann.foldPoints,
              fill: ann.color,
              closed: true,
              listening: false,
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
    />
  </div>
</template>
