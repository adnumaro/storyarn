<script setup>
import { computed, nextTick, ref, watch } from "vue";
import {
  AnnotationToolbar,
  ConditionToolbar,
  DialogueToolbar,
  EntryToolbar,
  ExitToolbar,
  HubToolbar,
  InstructionToolbar,
  JumpToolbar,
  SlugLineToolbar,
  SubflowToolbar,
} from "./toolbar-sections";

const {
  toolbarState,
  canEdit,
  hubs,
  projectFlows,
  sheetAvatars,
  subflowExits,
  referencingJumps,
  referencingFlows,
} = defineProps({
  toolbarState: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
  hubs: { type: Array, default: () => [] },
  projectFlows: { type: Array, default: () => [] },
  sheetAvatars: { type: Array, default: () => [] },
  subflowExits: { type: Array, default: () => [] },
  referencingJumps: { type: Array, default: () => [] },
  referencingFlows: { type: Array, default: () => [] },
});

const toolbarRef = ref(null);

const visible = computed(() => toolbarState.visible && canEdit);
const nodeType = computed(() => toolbarState.nodeType);
const nodeData = computed(() => toolbarState.nodeData || {});
const nodeId = computed(() => toolbarState.nodeId);

// Toolbar position style
const toolbarStyle = computed(() => {
  if (!visible.value) return { display: "none" };
  const s = toolbarState;
  const el = toolbarRef.value;
  const toolbarW = el?.offsetWidth || 200;
  const left = s.x + s.width / 2 - toolbarW / 2;
  const top = s.y - 48;
  return {
    display: "flex",
    left: `${Math.round(left)}px`,
    top: `${Math.round(top)}px`,
  };
});

watch([nodeType, visible], () => nextTick(() => {}));

// Map node types to toolbar components
const TOOLBAR_COMPONENTS = {
  entry: EntryToolbar,
  condition: ConditionToolbar,
  instruction: InstructionToolbar,
  hub: HubToolbar,
  annotation: AnnotationToolbar,
  dialogue: DialogueToolbar,
  jump: JumpToolbar,
  exit: ExitToolbar,
  subflow: SubflowToolbar,
  slug_line: SlugLineToolbar,
};

const activeComponent = computed(() => TOOLBAR_COMPONENTS[nodeType.value] || null);
</script>

<template>
  <div
    ref="toolbarRef"
    :style="toolbarStyle"
    class="absolute z-30 items-center gap-1.5 v2-surface-panel px-2 py-1.5 text-sm pointer-events-auto"
  >
    <component
      :is="activeComponent"
      v-if="activeComponent"
      :node-data="nodeData"
      :node-id="nodeId"
      :hubs="hubs"
      :project-flows="projectFlows"
      :sheet-avatars="sheetAvatars"
      :subflow-exits="subflowExits"
      :referencing-jumps="referencingJumps"
      :referencing-flows="referencingFlows"
    />
    <!-- Fallback for unknown types -->
    <span v-else class="text-xs opacity-50">{{ nodeType }}</span>
  </div>
</template>
