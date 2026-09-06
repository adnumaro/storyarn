<script setup lang="ts">
import { computed } from "vue";
import type { SequenceVisualLayer } from "../types";
import { compareSequenceLayers } from "../layerOrder";
import { finiteValue } from "../numbers";

const { layers = [] } = defineProps<{
  layers?: SequenceVisualLayer[];
}>();

const visibleLayers = computed(() =>
  [...layers]
    .filter((layer) => layer.visible !== false && Boolean(layer.url?.trim()))
    .sort(compareSequenceLayers),
);

function layerDepth(layer: SequenceVisualLayer): number {
  return layer.sequence_depth ?? layer.sequenceDepth ?? 0;
}

function normalized(value: number | null | undefined, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.min(1, Math.max(0, value));
}

function layerKey(layer: SequenceVisualLayer, index: number): string {
  return String(layer.key ?? layer.id ?? `${layer.url}:${index}`);
}

function layerFrameStyle(layer: SequenceVisualLayer, stackIndex: number) {
  const x = finiteValue(layer.x, 0);
  const y = finiteValue(layer.y, 0);
  const width = Math.max(0, finiteValue(layer.width, 1));
  const height = Math.max(0, finiteValue(layer.height, 1));
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
    zIndex: stackIndex,
  };
}

function layerImageStyle(layer: SequenceVisualLayer) {
  const fit = layer.fit || "contain";

  return {
    objectFit: fit,
    objectPosition: layerObjectPosition(layer, fit),
  };
}

function layerObjectPosition(layer: SequenceVisualLayer, fit: string): string {
  if (fit === "cover" || layer.slot === "full") return "center center";

  const anchorX = normalized(layer.anchor_x ?? layer.anchorX, 0.5);
  const anchorY = normalized(layer.anchor_y ?? layer.anchorY, 0.5);

  return `${horizontalObjectPosition(anchorX)} ${verticalObjectPosition(anchorY)}`;
}

function horizontalObjectPosition(anchorX: number): string {
  if (anchorX <= 0.25) return "left";
  if (anchorX >= 0.75) return "right";
  return "center";
}

function verticalObjectPosition(anchorY: number): string {
  if (anchorY <= 0.25) return "top";
  if (anchorY >= 0.75) return "bottom";
  return "center";
}
</script>

<template>
  <div
    class="sequence-visual-layers absolute inset-0 z-0 overflow-hidden pointer-events-none"
    aria-hidden="true"
  >
    <div
      v-for="(layer, index) in visibleLayers"
      :key="layerKey(layer, index)"
      class="sequence-visual-layer absolute block pointer-events-none"
      :style="layerFrameStyle(layer, index)"
      :data-sequence-id="layer.sequence_id ?? layer.sequenceId"
      :data-sequence-depth="layerDepth(layer)"
      :data-layer-id="layer.id"
      :data-kind="layer.kind"
      :data-slot="layer.slot ?? undefined"
      :data-origin-node-id="layer.origin?.nodeId ?? undefined"
      :data-origin-sequence-id="layer.origin?.sequenceId ?? undefined"
      :data-inherited="layer.origin?.inherited ?? undefined"
    >
      <img
        class="sequence-visual-layer-image block size-full pointer-events-none"
        :src="layer.url"
        :alt="layer.label || ''"
        :style="layerImageStyle(layer)"
        draggable="false"
      />
    </div>
  </div>
</template>
