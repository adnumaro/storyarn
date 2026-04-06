<script setup lang="ts">
import { useLive } from "@composables/useLive";
import {
  ToolbarColorPicker,
  ToolbarLayerPicker,
  ToolbarLockToggle,
  ToolbarSeparator,
  ToolbarSizePicker,
} from "../../toolbar";

interface AnnotationElement {
  id: number | string;
  color: string | null;
  fontSize: string | null;
  locked: boolean;
  layerId: number | string | null;
}

interface LayerData {
  id: number | string;
  name: string;
  visible: boolean;
}

const {
  element,
  layers = [],
  canEdit = false,
} = defineProps<{
  element: AnnotationElement;
  layers: LayerData[];
  canEdit: boolean;
}>();

const live = useLive();

function updateField(field: string, value: string | number | null): void {
  live.pushEvent("update_annotation", {
    id: String(element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function toggleLock(): void {
  updateField("locked", !element.locked ? "true" : "false");
}
</script>

<template>
  <ToolbarColorPicker
    :color="element.color || '#fbbf24'"
    :disabled="element.locked"
    @update:color="(c) => updateField('color', c)"
  />
  <ToolbarSizePicker
    :size="element.fontSize || 'md'"
    :disabled="element.locked"
    @update:size="(s) => updateField('font_size', s)"
  />
  <ToolbarSeparator />
  <ToolbarLayerPicker
    :layer-id="element.layerId"
    :layers="layers"
    :disabled="element.locked"
    @update:layer-id="(id) => updateField('layer_id', id)"
  />
  <ToolbarLockToggle :locked="element.locked || false" :disabled="!canEdit" @toggle="toggleLock" />
</template>
