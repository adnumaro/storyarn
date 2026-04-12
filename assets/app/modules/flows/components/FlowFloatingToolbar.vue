<script setup lang="ts">
import type { Component, CSSProperties } from "vue";
import { computed, nextTick, ref, watch } from "vue";
import type { NodeData } from "../lib/node-configs";
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

interface ToolbarState {
  visible: boolean;
  nodeId: string | number | null;
  reteNodeId: string | null;
  nodeType: string | null;
  nodeData: NodeData | null;
  x: number;
  y: number;
  width: number;
  height: number;
}

interface HubOption {
  id: number | string;
  name: string;
  color?: string;
}

interface FlowOption {
  id: number | string;
  name: string;
}

interface SheetAvatar {
  id: number | string;
  name: string;
  avatar_url?: string | null;
}

interface SubflowExit {
  id: string;
  label: string;
}

interface ReferencingJump {
  id: number | string;
  label: string;
  flow_name?: string;
}

interface ReferencingFlow {
  id: number | string;
  name: string;
}

const {
  toolbarState,
  canEdit = false,
  hubs = [],
  projectFlows = [],
  sheetAvatars = [],
  subflowExits = [],
  referencingJumps = [],
  referencingFlows = [],
} = defineProps<{
  toolbarState: ToolbarState;
  canEdit: boolean;
  hubs?: HubOption[];
  projectFlows?: FlowOption[];
  sheetAvatars?: SheetAvatar[];
  subflowExits?: SubflowExit[];
  referencingJumps?: ReferencingJump[];
  referencingFlows?: ReferencingFlow[];
}>();

const toolbarRef = ref<HTMLElement | null>(null);

const visible = computed(() => toolbarState.visible && canEdit);
const nodeType = computed(() => toolbarState.nodeType);
const nodeData = computed(() => toolbarState.nodeData || {});
const nodeId = computed(() => toolbarState.nodeId);

// Toolbar position style
const toolbarStyle = computed<CSSProperties>(() => {
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
const TOOLBAR_COMPONENTS: Record<string, Component> = {
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

const activeComponent = computed<Component | null>(() =>
  nodeType.value ? (TOOLBAR_COMPONENTS[nodeType.value] ?? null) : null,
);
</script>

<template>
  <div
    ref="toolbarRef"
    :style="toolbarStyle"
    class="absolute z-30 items-center gap-1.5 surface-panel px-2 py-1.5 text-sm pointer-events-auto"
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
