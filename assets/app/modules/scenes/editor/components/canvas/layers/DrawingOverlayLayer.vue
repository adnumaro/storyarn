<script setup lang="ts">
interface VertexCircleConfig {
  x: number;
  y: number;
  radius: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
}

interface DrawingOverlayData {
  ghostPoints: number[];
  previewLine: number[] | null;
  closeLine: number[] | null;
  vertexConfigs: VertexCircleConfig[];
}

const { drawingOverlay = null } = defineProps<{
  drawingOverlay: DrawingOverlayData | null;
}>();
</script>

<template>
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
    <v-circle v-for="(vc, i) in drawingOverlay.vertexConfigs" :key="'dv-' + i" :config="vc" />
  </v-layer>
</template>
