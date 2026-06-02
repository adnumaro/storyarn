<script setup lang="ts">
interface FogOverlayConfig {
  x: number;
  y: number;
  width: number;
  height: number;
  fill: string;
  opacity: number;
}

const { fogOverlayConfig } = defineProps<{
  fogOverlayConfig: FogOverlayConfig | null;
}>();
</script>

<template>
  <v-layer v-if="fogOverlayConfig" :config="{ listening: false }">
    <v-rect
      :config="{
        x: fogOverlayConfig.x,
        y: fogOverlayConfig.y,
        width: fogOverlayConfig.width,
        height: fogOverlayConfig.height,
        fill: fogOverlayConfig.fill,
        opacity: fogOverlayConfig.opacity,
        listening: false,
        perfectDrawEnabled: false,
      }"
    />
  </v-layer>
</template>
