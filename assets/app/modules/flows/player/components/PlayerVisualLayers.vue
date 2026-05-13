<script setup lang="ts">
import { computed } from "vue";

export interface PlayerVisualLayer {
  id: string | number;
  sequence_id?: string | number;
  sequenceId?: string | number;
  sequence_depth?: number | null;
  sequenceDepth?: number | null;
  kind: "backdrop" | "character" | "prop" | "overlay" | string;
  label?: string | null;
  url: string;
  z_index?: number | null;
  zIndex?: number | null;
  slot?: string | null;
  x?: number | null;
  y?: number | null;
  width?: number | null;
  height?: number | null;
  anchor_x?: number | null;
  anchorX?: number | null;
  anchor_y?: number | null;
  anchorY?: number | null;
  fit?: "cover" | "contain" | "fill" | null;
  opacity?: number | null;
}

const { layers = [] } = defineProps<{
  layers?: PlayerVisualLayer[];
}>();

const visibleLayers = computed(() =>
  [...layers]
    .filter((layer) => Boolean(layer.url))
    .sort((a, b) => {
      const depthDelta = layerDepth(a) - layerDepth(b);
      if (depthDelta !== 0) return depthDelta;
      const zDelta = layerZIndex(a) - layerZIndex(b);
      if (zDelta !== 0) return zDelta;
      return String(a.id).localeCompare(String(b.id));
    }),
);

function layerDepth(layer: PlayerVisualLayer): number {
  return layer.sequence_depth ?? layer.sequenceDepth ?? 0;
}

function layerZIndex(layer: PlayerVisualLayer): number {
  return layer.z_index ?? layer.zIndex ?? 0;
}

function normalized(value: number | null | undefined, fallback: number): number {
  if (typeof value !== "number" || Number.isNaN(value)) return fallback;
  return Math.min(1, Math.max(0, value));
}

function layerKey(layer: PlayerVisualLayer, index: number): string {
  return String(layer.id ?? `${layer.url}:${index}`);
}

function layerFrameStyle(layer: PlayerVisualLayer) {
  const depth = layerDepth(layer);
  const zIndex = layerZIndex(layer);
  const x = normalized(layer.x, 0);
  const y = normalized(layer.y, 0);
  const width = normalized(layer.width, 1);
  const height = normalized(layer.height, 1);
  const anchorX = normalized(layer.anchor_x ?? layer.anchorX, 0);
  const anchorY = normalized(layer.anchor_y ?? layer.anchorY, 0);
  const opacity = normalized(layer.opacity, 1);

  return {
    left: `${x * 100}%`,
    top: `${y * 100}%`,
    width: `${width * 100}%`,
    height: `${height * 100}%`,
    transform: `translate(${-anchorX * 100}%, ${-anchorY * 100}%)`,
    opacity,
    zIndex: depth * 1000 + zIndex,
  };
}

function layerImageStyle(layer: PlayerVisualLayer) {
  return {
    objectFit: layer.fit || "contain",
  };
}
</script>

<template>
  <div class="flow-player-stage-layers" aria-hidden="true">
    <div
      v-for="(layer, index) in visibleLayers"
      :key="layerKey(layer, index)"
      class="flow-player-stage-layer"
      :style="layerFrameStyle(layer)"
      :data-sequence-id="layer.sequence_id ?? layer.sequenceId"
      :data-sequence-depth="layerDepth(layer)"
      :data-kind="layer.kind"
      :data-slot="layer.slot ?? undefined"
    >
      <img
        class="flow-player-stage-layer-img flow-player-stage-layer-transition"
        :src="layer.url"
        :alt="layer.label || ''"
        :style="layerImageStyle(layer)"
      />
    </div>
  </div>
</template>
