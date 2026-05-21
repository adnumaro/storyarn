<script setup lang="ts">
interface BackgroundConfig {
  image: HTMLImageElement;
  x: number;
  y: number;
  width: number;
  height: number;
}

interface GridRectConfig {
  x: number;
  y: number;
  width: number;
  height: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
}

interface GridLineConfig {
  points: number[];
  stroke: string;
  strokeWidth: number;
  opacity: number;
}

const {
  backgroundConfig = null,
  gridRectConfig,
  gridLines,
} = defineProps<{
  backgroundConfig: BackgroundConfig | null;
  gridRectConfig: GridRectConfig;
  gridLines: GridLineConfig[];
}>();
</script>

<template>
  <v-layer :config="{ listening: false }">
    <v-image v-if="backgroundConfig" :config="backgroundConfig" />
    <template v-else>
      <v-rect :config="gridRectConfig" />
      <v-line v-for="(line, i) in gridLines" :key="'grid-' + i" :config="line" />
    </template>
  </v-layer>
</template>
