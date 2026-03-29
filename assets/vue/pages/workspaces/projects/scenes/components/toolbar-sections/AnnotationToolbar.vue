<script setup>
import { useLive } from "@/vue/composables/useLive";
import {
	ToolbarColorPicker,
	ToolbarLayerPicker,
	ToolbarLockToggle,
	ToolbarSeparator,
	ToolbarSizePicker,
} from "../../toolbar";

const props = defineProps({
	element: { type: Object, required: true },
	layers: { type: Array, default: () => [] },
	canEdit: { type: Boolean, default: false },
});

const live = useLive();

function updateField(field, value) {
	live.pushEvent("update_annotation", {
		id: String(props.element.id),
		field,
		value: value === null ? "" : String(value),
	});
}

function toggleLock() {
	updateField("locked", !props.element.locked ? "true" : "false");
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
  <ToolbarLockToggle
    :locked="element.locked || false"
    :disabled="!canEdit"
    @toggle="toggleLock"
  />
</template>
