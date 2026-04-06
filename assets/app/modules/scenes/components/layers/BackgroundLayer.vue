<script setup>
const { backgroundConfig, gridRectConfig, gridLines } = defineProps({
  backgroundConfig: { type: Object, default: null },
  gridRectConfig: { type: Object, required: true },
  gridLines: { type: Array, required: true },
});
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
