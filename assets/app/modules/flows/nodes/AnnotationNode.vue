<script setup lang="ts">
import { computed, inject, nextTick, ref, watch } from "vue";
import { FLOW_CONTEXT_KEY } from "../setup";
import type { FlowContextInjection, ReteEmitFn, ReteNodeData } from "../types";
import type { NodeConfig } from "../lib/node-configs";

interface AnnotationNodeData {
  text?: string;
  color?: string;
  font_size?: "sm" | "md" | "lg";
}

const { data, emit, config, color, nodeDataOverride = null } = defineProps<{
  data: ReteNodeData;
  emit: ReteEmitFn;
  config: NodeConfig;
  color: string;
  nodeDataOverride?: AnnotationNodeData | null;
}>();

const ctx = inject<FlowContextInjection>(FLOW_CONTEXT_KEY, {
  editingNodeId: null,
  onInlineEditSave: null,
  sheetsMap: {},
  hubsMap: {},
  lod: "full",
  nodeDataVersion: 0,
});
const textareaRef = ref<HTMLTextAreaElement | null>(null);

const nodeData = computed<AnnotationNodeData>(
  () => nodeDataOverride || (data.nodeData as AnnotationNodeData) || {},
);
const text = computed(() => nodeData.value.text || "");
const annColor = computed(() => nodeData.value.color || "#fbbf24");
const selected = computed(() => data.selected || false);
const editing = computed(() => ctx.editingNodeId === data.id);

const sizeClass = computed(() => {
  const fs = nodeData.value.font_size || "md";
  if (fs === "sm") return "annotation-sm";
  if (fs === "lg") return "annotation-lg";
  return "annotation-md";
});

// Autofocus textarea when entering edit mode
watch(editing, (val) => {
  if (val) {
    nextTick(() => textareaRef.value?.focus());
  }
});

function onBlur(e: FocusEvent) {
  const val = (e.target as HTMLTextAreaElement).value;
  if (val !== text.value) {
    ctx.onInlineEditSave?.(data.id, "text", val);
  }
}

function onKeydown(e: KeyboardEvent) {
  e.stopPropagation();
  if (e.key === "Escape") (e.target as HTMLTextAreaElement).blur();
}
</script>

<template>
  <div
    :class="['annotation-wrapper', sizeClass, { selected }]"
    :style="{ '--ann-color': annColor }"
    data-testid="node"
  >
    <div class="annotation-bg" />

    <!-- Edit mode -->
    <textarea
      v-if="editing"
      ref="textareaRef"
      class="annotation-text annotation-edit-textarea"
      :value="text"
      :placeholder="$t('flows.annotation.placeholder')"
      @blur="onBlur"
      @keydown="onKeydown"
      @pointerdown.stop
    />

    <!-- View mode -->
    <div v-else class="annotation-text">{{ text || "…" }}</div>

    <div class="annotation-fold" />
  </div>
</template>

<style scoped>
.annotation-wrapper {
  position: relative;
  width: 200px;
  height: 120px;
  cursor: default;
  border-radius: 2px;
  overflow: hidden;
}

.annotation-bg {
  position: absolute;
  inset: 0;
  opacity: 0.82;
  background-color: var(--ann-color);
  border-radius: 2px;
  clip-path: polygon(0 0, calc(100% - 14px) 0, 100% 14px, 100% 100%, 0 100%);
}

.annotation-text {
  position: relative;
  font-weight: 600;
  line-height: 1.4;
  white-space: pre-wrap;
  word-break: break-word;
  color: rgba(0, 0, 0, 0.75);
}

.annotation-edit-textarea {
  width: 100%;
  height: 100%;
  background: transparent;
  border: 0;
  resize: none;
  outline: none;
  font-family: inherit;
  cursor: text;
}

.annotation-fold {
  position: absolute;
  top: 0;
  right: 0;
  width: 14px;
  height: 14px;
  background: color-mix(in oklch, var(--ann-color) 65%, black);
  clip-path: polygon(0 0, 100% 100%, 0 100%);
}

.annotation-sm .annotation-text {
  font-size: 11px;
  padding: 4px calc(8px + 14px) 6px 8px;
}

.annotation-md .annotation-text {
  font-size: 14px;
  padding: 6px calc(10px + 14px) 8px 10px;
}

.annotation-lg .annotation-text {
  font-size: 17px;
  padding: 8px calc(12px + 14px) 10px 12px;
}

.annotation-wrapper.selected {
  outline: 2px solid color-mix(in oklch, var(--color-primary, #3b82f6) 70%, transparent);
  outline-offset: 2px;
}
</style>
