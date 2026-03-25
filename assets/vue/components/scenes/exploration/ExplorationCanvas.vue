<script setup>
import { computed, ref, toRef } from "vue";
import { useConnections } from "../composables/useConnections";
import { useKonvaStage } from "../composables/useKonvaStage";
import { usePins } from "../composables/usePins";
import { useZones } from "../composables/useZones";
import { useLive } from "@/vue/composables/useLive";
import { useExplorationInteraction } from "./composables/useExplorationInteraction";

const props = defineProps({
	sceneData: { type: Object, default: null },
	explorationData: { type: Object, required: true },
	showZones: { type: Boolean, default: false },
});

const containerRef = ref(null);
const live = useLive();

// --- Stage (pan/zoom/background) ---
const {
	stageConfig,
	stageRef,
	backgroundConfig,
	cursorStyle,
	handleWheel,
	percentToPixel,
} = useKonvaStage({
	containerRef,
	sceneData: toRef(props, "sceneData"),
	activeTool: ref("pan"),
	editMode: ref(false),
});

// --- Static refs for read-only mode ---
const nullRef = ref(null);
const falseRef = ref(false);
const emptyObj = ref({});
const emptyArr = ref([]);

// --- Filter visible elements from exploration data ---
const allZones = computed(() => props.explorationData?.zones || []);
const allPins = computed(() => props.explorationData?.pins || []);

const visiblePins = computed(() =>
	allPins.value.filter((p) => p.visibility !== "hide"),
);
const visibleZones = computed(() =>
	allZones.value.filter((z) => z.visibility !== "hide"),
);
const connections = computed(
	() => props.explorationData?.connections || [],
);

// --- Visibility lookup maps ---
const zoneVisibility = computed(() =>
	Object.fromEntries(allZones.value.map((z) => [z.id, z.visibility])),
);
const pinVisibility = computed(() =>
	Object.fromEntries(allPins.value.map((p) => [p.id, p.visibility])),
);

// --- Interaction ---
const {
	handleZoneClick,
	handlePinClick,
	zoneShowOverride,
	clickableZoneIds,
	clickablePinIds,
} = useExplorationInteraction({
	pushEvent: live.pushEvent,
	explorationZones: allZones,
	explorationPins: allPins,
	showZones: toRef(props, "showZones"),
});

// --- Composables in read-only mode ---
const { pinConfigs } = usePins({
	pins: visiblePins,
	layers: emptyArr,
	entityLocks: emptyObj,
	currentUserId: ref(0),
	percentToPixel,
	activeTool: ref("pan"),
	selectedType: nullRef,
	selectedId: nullRef,
	isSelectMode: falseRef,
	editMode: falseRef,
	canEdit: falseRef,
});

const { zoneConfigs } = useZones({
	zones: visibleZones,
	layers: emptyArr,
	entityLocks: emptyObj,
	currentUserId: ref(0),
	percentToPixel,
	selectedType: nullRef,
	selectedId: nullRef,
	isSelectMode: falseRef,
	zoneDragOverride: nullRef,
	editingZoneId: nullRef,
	editingVertices: emptyArr,
});

const { connectionConfigs } = useConnections({
	connections,
	pins: visiblePins,
	layers: emptyArr,
	percentToPixel,
	selectedType: nullRef,
	selectedId: nullRef,
	isSelectMode: falseRef,
	dragOverrides: emptyObj,
});

// --- Helpers ---
function clipCircle(radius) {
	return (ctx) => {
		ctx.arc(0, 0, radius, 0, Math.PI * 2);
	};
}

function getZoneFill(zone) {
	const raw = allZones.value.find((z) => z.id === zone.id);
	if (!raw) return { fill: "transparent", opacity: 0 };
	const override = zoneShowOverride(raw);
	if (override) return override;
	// Default: zones are invisible in exploration (only visible with show-zones)
	return { fill: "transparent", opacity: 0 };
}

function getElementOpacity(id, visMap, fallback) {
	return visMap[id] === "disable" ? 0.3 : fallback;
}

const LABEL_COLOR = "#d1d5db";
</script>

<template>
  <div ref="containerRef" class="w-full h-full relative" :style="{ cursor: cursorStyle }">
    <v-stage ref="stageRef" :config="stageConfig" @wheel="handleWheel">
      <!-- Background layer -->
      <v-layer :config="{ listening: false }">
        <v-image v-if="backgroundConfig" :config="backgroundConfig" />
      </v-layer>

      <!-- Zones + Connections layer -->
      <v-layer>
        <v-group
          v-for="zone in zoneConfigs"
          :key="'zone-' + zone.id"
          :config="{ listening: clickableZoneIds.has(zone.id) }"
          @click="() => handleZoneClick(zone.id)"
        >
          <v-line
            :config="{
              points: zone.points,
              fill: getZoneFill(zone).fill,
              stroke: zone.stroke,
              strokeWidth: zone.strokeWidth,
              dash: zone.dash,
              opacity: getElementOpacity(zone.id, zoneVisibility, getZoneFill(zone).opacity),
              closed: true,
              hitStrokeWidth: zone.hitStrokeWidth,
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
        </v-group>
        <v-group
          v-for="conn in connectionConfigs"
          :key="'conn-' + conn.id"
          :config="{ listening: false }"
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
            }"
          />
          <v-text v-if="conn.labelConfig" :config="conn.labelConfig" />
        </v-group>
      </v-layer>

      <!-- Pins layer -->
      <v-layer>
        <v-group
          v-for="pin in pinConfigs"
          :key="'pin-' + pin.id"
          :config="{
            x: pin.x,
            y: pin.y,
            listening: clickablePinIds.has(pin.id),
            opacity: getElementOpacity(pin.id, pinVisibility, pin.opacity ?? 1),
          }"
          @click="() => handlePinClick(pin.id)"
        >
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
        </v-group>
      </v-layer>
    </v-stage>
  </div>
</template>
