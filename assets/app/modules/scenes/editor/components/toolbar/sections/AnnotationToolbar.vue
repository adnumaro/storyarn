<script setup lang="ts">
import { useLive } from "@shared/composables/useLive.ts";
import { useSceneElementOptimisticUpdater } from "../../../composables/useSceneElementOptimism";
import {
  ToolbarColorPicker,
  ToolbarLayerPicker,
  ToolbarLockToggle,
  ToolbarSeparator,
  ToolbarSizePicker,
} from "../controls";

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
const updateOptimistically = useSceneElementOptimisticUpdater();

const FIELD_TO_PROP: Record<string, keyof AnnotationElement> = {
  color: "color",
  font_size: "fontSize",
  layer_id: "layerId",
  locked: "locked",
};

function updateField(field: string, value: string | number | null): void {
  const prop = FIELD_TO_PROP[field];
  if (prop) updateOptimistically("annotation", element.id, { [prop]: value });

  live.pushEvent("update_annotation", {
    id: String(element.id),
    field,
    value: value === null ? "" : String(value),
  });
}

function toggleLock(): void {
  const nextLocked = !element.locked;
  updateOptimistically("annotation", element.id, { locked: nextLocked });

  live.pushEvent("update_annotation", {
    id: String(element.id),
    field: "locked",
    value: String(nextLocked),
  });
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
