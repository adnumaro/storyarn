<script setup lang="ts">
import { ref, watch } from "vue";
import type Konva from "konva";
import type { BubbleData } from "./composables/useAmbientDisplay";

interface StageRefProxy {
  getStage: () => Konva.Stage | undefined;
}

const {
  bubble = null,
  getPinNode,
  stageRef = null,
} = defineProps<{
  bubble?: BubbleData | null;
  getPinNode: (pinId: number | string) => Konva.Node | null;
  stageRef?: StageRefProxy | null;
}>();

const position = ref({ x: 0, y: 0 });

// Update position from Konva pin → screen coords
function updatePosition() {
  if (!bubble || !getPinNode || !stageRef) return;

  const node = getPinNode(bubble.pinId);
  if (!node) return;

  const stage = stageRef.getStage?.();
  if (!stage) return;

  const absPos = node.getAbsolutePosition();
  const container = stage.container();
  const rect = container.getBoundingClientRect();

  position.value = {
    x: rect.left + absPos.x,
    y: rect.top + absPos.y,
  };
}

watch(
  () => bubble,
  (b) => {
    if (b) requestAnimationFrame(updatePosition);
  },
  { immediate: true },
);
</script>

<template>
  <Teleport to="body">
    <div
      v-if="bubble"
      class="fixed z-50 pointer-events-none"
      :style="{
        left: position.x + 'px',
        top: position.y + 'px',
        transform: 'translate(-50%, -100%) translateY(-24px)',
      }"
    >
      <div
        class="bg-background/95 backdrop-blur-sm border border-border rounded-lg px-3 py-2 max-w-xs shadow-lg animate-in fade-in slide-in-from-bottom-2 duration-200"
      >
        <div v-if="bubble.speaker" class="text-xs font-semibold text-primary mb-0.5">
          {{ bubble.speaker }}
        </div>
        <div class="text-sm text-foreground leading-relaxed">
          {{ bubble.text }}
        </div>
      </div>
    </div>
  </Teleport>
</template>
