<script setup>
import { ArrowLeftRight, Settings, Tag } from "lucide-vue-next";
import { computed, nextTick, ref, watch } from "vue";
import { useLive } from "@/vue/composables/useLive";
import {
	ToolbarColorPicker,
	ToolbarLayerPicker,
	ToolbarLockToggle,
	ToolbarSeparator,
	ToolbarSizePicker,
	ToolbarStrokePicker,
} from "./toolbar";

const props = defineProps({
	selectedType: { type: String, default: null },
	selectedId: { type: [Number, null], default: null },
	annotations: { type: Array, default: () => [] },
	connections: { type: Array, default: () => [] },
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

const selectedConnection = computed(() => {
	if (props.selectedType !== "connection") return null;
	return props.connections.find((c) => c.id === props.selectedId) || null;
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

function toggleField(event, field, currentValue) {
	if (!props.selectedId) return;
	live.pushEvent(event, {
		id: String(props.selectedId),
		field,
		toggle: String(!currentValue),
	});
}

function toggleAnnotationLock() {
	if (!selectedAnnotation.value) return;
	updateField(
		"update_annotation",
		"locked",
		!selectedAnnotation.value.locked ? "true" : "false",
	);
}

function openElementPanel() {
	live.pushEvent("open_element_panel", {});
}

function onLabelBlur(event, updateEvent) {
	updateField(updateEvent, "label", event.target.value);
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
        @toggle="toggleAnnotationLock"
      />
    </template>

    <!-- Connection toolbar -->
    <template v-if="selectedType === 'connection' && selectedConnection">
      <!-- Label input -->
      <input
        type="text"
        :value="selectedConnection.label || ''"
        class="v2-toolbar-input w-24"
        placeholder="Label"
        :disabled="!canEdit"
        @blur="(e) => onLabelBlur(e, 'update_connection')"
        @keydown.enter="$event.target.blur()"
      />
      <ToolbarSeparator />

      <!-- Stroke picker (style + width + color) -->
      <ToolbarStrokePicker
        :line-style="selectedConnection.lineStyle || 'solid'"
        :line-width="selectedConnection.lineWidth || 2"
        :color="selectedConnection.color || '#ffffff'"
        :disabled="!canEdit"
        @update:line-style="(v) => updateField('update_connection', 'line_style', v)"
        @update:line-width="(v) => updateField('update_connection', 'line_width', v)"
        @update:color="(v) => updateField('update_connection', 'color', v)"
      />
      <ToolbarSeparator />

      <!-- Show Label toggle -->
      <button
        type="button"
        class="v2-toolbar-btn px-1.5"
        :class="{ '!bg-accent': selectedConnection.showLabel }"
        title="Show Label"
        :disabled="!canEdit"
        @click="toggleField('update_connection', 'show_label', selectedConnection.showLabel)"
      >
        <Tag class="size-3" />
      </button>

      <!-- Bidirectional toggle -->
      <button
        type="button"
        class="v2-toolbar-btn px-1.5"
        :class="{ '!bg-accent': selectedConnection.bidirectional }"
        title="Bidirectional"
        :disabled="!canEdit"
        @click="toggleField('update_connection', 'bidirectional', selectedConnection.bidirectional)"
      >
        <ArrowLeftRight class="size-3" />
      </button>
      <ToolbarSeparator />

      <!-- Settings cog -->
      <button
        type="button"
        class="v2-toolbar-btn"
        title="Properties"
        @click="openElementPanel"
      >
        <Settings class="size-3.5" />
      </button>
    </template>

    <!-- Future: pin, zone toolbars -->
  </div>
</template>
