<script setup>
import { computed, nextTick, ref, watch } from "vue";
import {
  AnnotationToolbar,
  ConnectionToolbar,
  PinToolbar,
  ZoneToolbar,
} from "./toolbar-sections/index.js";

const { selectedType, selectedElement, layers, canEdit, editMode, stageConfig, elementPosition, isDragging } = defineProps({
  selectedType: { type: String, default: null },
  selectedElement: { type: Object, default: null },
  layers: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
  editMode: { type: Boolean, default: true },
  stageConfig: { type: Object, required: true },
  elementPosition: { type: Object, default: null },
  isDragging: { type: Boolean, default: false },
});

const toolbarRef = ref(null);
const toolbarStyle = ref({ display: "none" });

const visible = computed(
  () => selectedType !== null && selectedElement !== null && canEdit && editMode,
);

const TOOLBAR_COMPONENTS = {
  annotation: AnnotationToolbar,
  connection: ConnectionToolbar,
  pin: PinToolbar,
  zone: ZoneToolbar,
};

const activeComponent = computed(() => TOOLBAR_COMPONENTS[selectedType] || null);

function updatePosition() {
  if (!visible.value || !elementPosition) {
    toolbarStyle.value = { display: "none" };
    return;
  }

  const pos = elementPosition;
  const scale = stageConfig.scaleX;
  const screenX = pos.x * scale + stageConfig.x;
  const screenY = pos.y * scale + stageConfig.y;
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
    () => selectedElement,
    () => stageConfig.scaleX,
    () => stageConfig.x,
    () => stageConfig.y,
    () => elementPosition,
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
      :layers="layers"
      :can-edit="canEdit"
    />
  </div>
</template>
