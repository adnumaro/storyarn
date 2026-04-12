<script setup lang="ts">
import { Trash2 } from "lucide-vue-next";
import {
  ToolbarColorPicker,
  ToolbarSeparator,
  ToolbarSizePicker,
} from "@components/toolbar/index.ts";
import { useLive } from "@composables/useLive";
import type { NodeData } from "../../lib/node-configs";

interface AnnotationNodeData extends NodeData {
  color?: string;
  font_size?: "sm" | "md" | "lg";
}

const { nodeData, nodeId } = defineProps<{
  nodeData: AnnotationNodeData;
  nodeId: string | number;
}>();

const live = useLive();

function updateAnnotationColor(color: string) {
  live.pushEvent("update_annotation_color", { value: color });
}

function updateAnnotationFontSize(size: string) {
  live.pushEvent("update_annotation_font_size", { value: size });
}

function deleteNode() {
  live.pushEvent("delete_node", { id: nodeId });
}
</script>

<template>
  <ToolbarColorPicker :color="nodeData.color || '#fbbf24'" @update:color="updateAnnotationColor" />
  <ToolbarSizePicker :size="nodeData.font_size || 'md'" @update:size="updateAnnotationFontSize" />
  <ToolbarSeparator />
  <button type="button" class="toolbar-btn text-destructive" title="Delete" @click="deleteNode">
    <Trash2 class="size-3.5" />
  </button>
</template>
