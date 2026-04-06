<script setup>
import { Trash2 } from "lucide-vue-next";
import {
  ToolbarColorPicker,
  ToolbarSeparator,
  ToolbarSizePicker,
} from "@components/toolbar/index.js";
import { useLive } from "@composables/useLive.js";

const { nodeData, nodeId } = defineProps({
  nodeData: { type: Object, required: true },
  nodeId: { type: [String, Number], required: true },
});

const live = useLive();

function updateAnnotationColor(color) {
  live.pushEvent("update_annotation_color", { value: color });
}

function updateAnnotationFontSize(size) {
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
  <button type="button" class="v2-toolbar-btn text-destructive" title="Delete" @click="deleteNode">
    <Trash2 class="size-3.5" />
  </button>
</template>
