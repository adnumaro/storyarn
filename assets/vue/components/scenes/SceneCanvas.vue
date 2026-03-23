<script setup>
import { ref, toRef } from "vue";
import { useKonvaStage } from "./composables/useKonvaStage";

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
} = useKonvaStage({
	containerRef,
	sceneData: toRef(props, "sceneData"),
	activeTool: toRef(props, "activeTool"),
	editMode: toRef(props, "editMode"),
});
</script>

<template>
  <div ref="containerRef" class="w-full h-full" :style="{ cursor: cursorStyle }">
    <v-stage ref="stageRef" :config="stageConfig" @wheel="handleWheel">
      <v-layer>
        <v-image v-if="backgroundConfig" :config="backgroundConfig" />
        <template v-else>
          <v-rect :config="gridRectConfig" />
          <v-line v-for="(line, i) in gridLines" :key="'grid-' + i" :config="line" />
        </template>
      </v-layer>
      <!-- Phases 4B-4G: element layers here -->
    </v-stage>
  </div>
</template>
