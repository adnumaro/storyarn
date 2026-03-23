<script setup>
import { ref, toRef } from "vue";
import { useKonvaStage } from "./composables/useKonvaStage";
import { usePins } from "./composables/usePins";

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

      <!-- Phases 4C-4G: zones, connections, annotations, selection -->
    </v-stage>
  </div>
</template>
