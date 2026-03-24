<script setup>
import { computed, nextTick, ref, watch } from "vue";
import { useLive } from "@/vue/composables/useLive";
import {
	ToolbarColorPicker,
	ToolbarLayerPicker,
	ToolbarLockToggle,
	ToolbarSeparator,
	ToolbarSizePicker,
} from "./toolbar";

const props = defineProps({
	selectedType: { type: String, default: null },
	selectedId: { type: [Number, null], default: null },
	annotations: { type: Array, default: () => [] },
	layers: { type: Array, default: () => [] },
	canEdit: { type: Boolean, default: false },
	editMode: { type: Boolean, default: true },
	stageConfig: { type: Object, required: true },
	elementPosition: { type: Object, default: null },
	containerWidth: { type: Number, default: 800 },
});

const live = useLive();
const toolbarRef = ref(null);
const toolbarStyle = ref({ display: "none" });

const visible = computed(
	() =>
		props.selectedType !== null &&
		props.selectedId !== null &&
		props.canEdit &&
		props.editMode,
);

const selectedAnnotation = computed(() => {
	if (props.selectedType !== "annotation") return null;
	return props.annotations.find((a) => a.id === props.selectedId) || null;
});

function updatePosition() {
	if (!visible.value || !props.elementPosition) {
		toolbarStyle.value = { display: "none" };
		return;
	}

	const pos = props.elementPosition;
	const scale = props.stageConfig.scaleX;
	const screenX = pos.x * scale + props.stageConfig.x;
	const screenY = pos.y * scale + props.stageConfig.y;

	const el = toolbarRef.value;
	const toolbarW = el?.offsetWidth || 200;
	const toolbarH = el?.offsetHeight || 36;

	let left = screenX - toolbarW / 2 + (pos.width * scale) / 2;
	let top = screenY - toolbarH - 12;

	left = Math.max(8, Math.min(left, props.containerWidth - toolbarW - 8));
	if (top < 8) top = screenY + (pos.height || 0) * scale + 12;

	toolbarStyle.value = {
		display: "flex",
		left: `${Math.round(left)}px`,
		top: `${Math.round(top)}px`,
	};
}

watch(
	[
		() => props.selectedId,
		() => props.stageConfig.scaleX,
		() => props.stageConfig.x,
		() => props.stageConfig.y,
		() => props.elementPosition,
	],
	() => nextTick(updatePosition),
	{ immediate: true },
);

watch(visible, (v) => {
	if (v) nextTick(updatePosition);
	else toolbarStyle.value = { display: "none" };
});

function updateField(event, field, value) {
	if (!props.selectedId) return;
	live.pushEvent(event, {
		id: String(props.selectedId),
		field,
		value: value === null ? "" : String(value),
	});
}

function toggleLock() {
	if (!selectedAnnotation.value) return;
	updateField(
		"update_annotation",
		"locked",
		!selectedAnnotation.value.locked ? "true" : "false",
	);
}
</script>

<template>
  <div
    v-if="visible"
    ref="toolbarRef"
    class="absolute z-[1050] v2-surface-panel px-1.5 py-1 flex items-center gap-0.5"
    :style="toolbarStyle"
  >
    <!-- Annotation toolbar -->
    <template v-if="selectedType === 'annotation' && selectedAnnotation">
      <ToolbarColorPicker
        :color="selectedAnnotation.color || '#fbbf24'"
        :disabled="selectedAnnotation.locked"
        @update:color="(c) => updateField('update_annotation', 'color', c)"
      />
      <ToolbarSizePicker
        :size="selectedAnnotation.fontSize || 'md'"
        :disabled="selectedAnnotation.locked"
        @update:size="(s) => updateField('update_annotation', 'font_size', s)"
      />
      <ToolbarSeparator />
      <ToolbarLayerPicker
        :layer-id="selectedAnnotation.layerId"
        :layers="layers"
        :disabled="selectedAnnotation.locked"
        @update:layer-id="(id) => updateField('update_annotation', 'layer_id', id)"
      />
      <ToolbarLockToggle
        :locked="selectedAnnotation.locked || false"
        :disabled="!canEdit"
        @toggle="toggleLock"
      />
    </template>

    <!-- Future: pin, zone, connection toolbars -->
  </div>
</template>
