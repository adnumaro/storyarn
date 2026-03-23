<script setup>
import { ref, toRef } from "vue";
import { useConnections } from "./composables/useConnections";
import { useKonvaStage } from "./composables/useKonvaStage";
import { usePins } from "./composables/usePins";
import { useZones } from "./composables/useZones";

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
	activeTool: toRef(props, "activeTool"),
	editMode: toRef(props, "editMode"),
});

const { pinConfigs } = usePins({
	pins: toRef(props, "pins"),
	layers: toRef(props, "layers"),
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
	percentToPixel,
});

const { zoneConfigs } = useZones({
	zones: toRef(props, "zones"),
	layers: toRef(props, "layers"),
	entityLocks: toRef(props, "entityLocks"),
	currentUserId: toRef(props, "currentUserId"),
	percentToPixel,
});

const { connectionConfigs } = useConnections({
	connections: toRef(props, "connections"),
	pins: toRef(props, "pins"),
	layers: toRef(props, "layers"),
	percentToPixel,
});

function clipCircle(radius) {
	return (ctx) => {
		ctx.arc(0, 0, radius, 0, Math.PI * 2);
	};
}

const LABEL_COLOR = "#d1d5db";
</script>

<template>
  <div ref="containerRef" class="w-full h-full" :style="{ cursor: cursorStyle }">
    <v-stage ref="stageRef" :config="stageConfig" @wheel="handleWheel">
      <!-- Background layer -->
      <v-layer>
        <v-image v-if="backgroundConfig" :config="backgroundConfig" />
        <template v-else>
          <v-rect :config="gridRectConfig" />
          <v-line v-for="(line, i) in gridLines" :key="'grid-' + i" :config="line" />
        </template>
      </v-layer>

      <!-- Zone layer (below pins) -->
      <v-layer>
        <v-group v-for="zone in zoneConfigs" :key="'zone-' + zone.id">
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
              listening: false,
            }"
          />

          <!-- Zone label at centroid -->
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

          <!-- Lock badge -->
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

      <!-- Connection layer (between zones and pins) -->
      <v-layer>
        <v-group v-for="conn in connectionConfigs" :key="'conn-' + conn.id">
          <!-- Main line -->
          <v-line
            :config="{
              points: conn.points,
              stroke: conn.stroke,
              strokeWidth: conn.strokeWidth,
              dash: conn.dash,
              opacity: conn.opacity,
              listening: false,
            }"
          />

          <!-- Forward arrowhead -->
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

          <!-- Reverse arrowhead (bidirectional) -->
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

          <!-- Label -->
          <v-text v-if="conn.labelConfig" :config="conn.labelConfig" />
        </v-group>
      </v-layer>

      <!-- Pin layer -->
      <v-layer>
        <v-group
          v-for="pin in pinConfigs"
          :key="'pin-' + pin.id"
          :config="{ x: pin.x, y: pin.y }"
        >
          <!-- Icon pin (pre-rendered Lucide icon circle) -->
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

          <!-- Initials pin (pre-rendered initials circle) -->
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

          <!-- Avatar/asset image pin -->
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

          <!-- Label below pin -->
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
            }"
          />

          <!-- Lock badge -->
          <v-image
            v-if="pin.lockBadge"
            :config="{
              image: pin.lockBadge,
              x: pin.radius - 10,
              y: -pin.radius - 4,
              width: 14,
              height: 14,
            }"
          />
        </v-group>
      </v-layer>

      <!-- Phases 4D-4G: connections, annotations, selection -->
    </v-stage>
  </div>
</template>
