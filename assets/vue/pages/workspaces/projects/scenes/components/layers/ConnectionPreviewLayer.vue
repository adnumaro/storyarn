<script setup>
defineProps({
	connectionPreviewLine: { type: Array, default: null },
	previewStroke: { type: String, required: true },
});
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
