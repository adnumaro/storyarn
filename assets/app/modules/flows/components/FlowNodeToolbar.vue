<script setup lang="ts">
import type { Component, CSSProperties } from "vue";
import { computed } from "vue";

defineOptions({ inheritAttrs: false });
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
  SequenceToolbar,
  SubflowToolbar,
} from "./toolbar-sections";

const {
  nodeType,
  nodeData = {},
  nodeId = null,
  zoom = 1,
  hubs = [],
  projectFlows = [],
  sheetAvatars = [],
  subflowExits = [],
  referencingJumps = [],
  referencingFlows = [],
} = defineProps<{
  nodeType: string;
  nodeData?: NodeData | Record<string, unknown>;
  nodeId?: string | number | null;
  zoom?: number;
  hubs?: unknown[];
  projectFlows?: unknown[];
  sheetAvatars?: unknown[];
  subflowExits?: unknown[];
  referencingJumps?: unknown[];
  referencingFlows?: unknown[];
}>();

const inverseScale = computed(() => 1 / (zoom || 1));

const TOOLBAR_COMPONENTS: Record<string, Component> = {
  entry: EntryToolbar,
  condition: ConditionToolbar,
  instruction: InstructionToolbar,
  hub: HubToolbar,
  annotation: AnnotationToolbar,
  dialogue: DialogueToolbar,
  jump: JumpToolbar,
  exit: ExitToolbar,
  sequence: SequenceToolbar,
  subflow: SubflowToolbar,
};

const activeComponent = computed<Component | null>(() => TOOLBAR_COMPONENTS[nodeType] ?? null);
</script>

<template>
  <div
    class="absolute bottom-full left-1/2 z-30 flex items-center gap-1.5 surface-panel px-2 py-1.5 text-sm pointer-events-auto whitespace-nowrap"
    @pointerdown.stop
    @mousedown.stop
    @click.stop
    :style="{
      transform: `translateX(-50%) scale(${inverseScale})`,
      transformOrigin: 'bottom center',
      marginBottom: `${8 * inverseScale}px`,
    }"
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
    <span v-else class="text-xs opacity-50">{{ nodeType }}</span>
  </div>
</template>
