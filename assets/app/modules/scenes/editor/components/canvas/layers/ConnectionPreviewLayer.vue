<script setup lang="ts">
const { connectionPreviewLine = null, previewStroke } = defineProps<{
  connectionPreviewLine: number[] | null;
  previewStroke: string;
}>();
</script>

<template>
  <v-layer v-if="connectionPreviewLine" :config="{ listening: false }">
    <v-line
      :config="{
        points: connectionPreviewLine,
        stroke: previewStroke,
        strokeWidth: 2,
        dash: [8, 4],
        listening: false,
      }"
    />
  </v-layer>
</template>
