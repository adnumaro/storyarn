<script setup>
import { computed, nextTick, ref, watch } from "vue";
import {
	AnnotationToolbar,
	ConnectionToolbar,
	PinToolbar,
	ZoneToolbar,
} from "./toolbar-sections/index.js";

const props = defineProps({
	selectedType: { type: String, default: null },
	selectedId: { type: [Number, null], default: null },
	annotations: { type: Array, default: () => [] },
	connections: { type: Array, default: () => [] },
	pins: { type: Array, default: () => [] },
	zones: { type: Array, default: () => [] },
	layers: { type: Array, default: () => [] },
	canEdit: { type: Boolean, default: false },
	editMode: { type: Boolean, default: true },
	stageConfig: { type: Object, required: true },
	elementPosition: { type: Object, default: null },
	containerWidth: { type: Number, default: 800 },
	isDragging: { type: Boolean, default: false },
});

const toolbarRef = ref(null);
const toolbarStyle = ref({ display: "none" });

const visible = computed(
	() =>
		props.selectedType !== null &&
		props.selectedId !== null &&
		props.canEdit &&
		props.editMode,
);

const ELEMENT_LISTS = {
	annotation: "annotations",
	connection: "connections",
	pin: "pins",
	zone: "zones",
};

const TOOLBAR_COMPONENTS = {
	annotation: AnnotationToolbar,
	connection: ConnectionToolbar,
	pin: PinToolbar,
	zone: ZoneToolbar,
};

const selectedElement = computed(() => {
	const listKey = ELEMENT_LISTS[props.selectedType];
	if (!listKey) return null;
	return props[listKey].find((e) => e.id === props.selectedId) || null;
});

const activeComponent = computed(
	() => TOOLBAR_COMPONENTS[props.selectedType] || null,
);

function updatePosition() {
	if (!visible.value || !props.elementPosition) {
		toolbarStyle.value = { display: "none" };
		return;
	}

	const pos = props.elementPosition;
	const scale = props.stageConfig.scaleX;
	const screenX = pos.x * scale + props.stageConfig.x;
	const screenY = pos.y * scale + props.stageConfig.y;
	const screenW = (pos.width || 0) * scale;
	const screenH = (pos.height || 0) * scale;

	const el = toolbarRef.value;
	const toolbarW = el?.offsetWidth || 200;
	const toolbarH = el?.offsetHeight || 36;

	const left = screenX + screenW / 2 - toolbarW / 2;
	const top = screenY - toolbarH - 12;

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
</script>

<template>
  <div
    v-if="visible"
    ref="toolbarRef"
    class="absolute z-30 v2-surface-panel px-1.5 py-1 flex items-center gap-0.5 transition-opacity duration-200"
    :class="isDragging ? 'opacity-0 pointer-events-none delay-0' : 'opacity-100 delay-400'"
    :style="toolbarStyle"
  >
    <component
      :is="activeComponent"
      v-if="activeComponent && selectedElement"
      :element="selectedElement"
      :selected-id="selectedId"
      :layers="layers"
      :can-edit="canEdit"
    />
  </div>
</template>
