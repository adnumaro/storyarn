<script setup lang="ts">
import type { Component } from "vue";
import { computed, inject } from "vue";
import type { FlowNodeType, NodeData } from "../lib/node-configs";
import { NODE_CONFIGS } from "../lib/node-configs";
import { resolveNodeColor } from "../lib/render-helpers";
import type { SheetMapEntry, HubMapEntry } from "../types";
import AnnotationNode from "../nodes/AnnotationNode.vue";
import ConditionNode from "../nodes/ConditionNode.vue";
import DialogueNode from "../nodes/DialogueNode.vue";
import EntryNode from "../nodes/EntryNode.vue";
import ExitNode from "../nodes/ExitNode.vue";
import HubNode from "../nodes/HubNode.vue";
import InstructionNode from "../nodes/InstructionNode.vue";
import JumpNode from "../nodes/JumpNode.vue";
import SubflowNode from "../nodes/SubflowNode.vue";
import { FLOW_CONTEXT_KEY } from "../setup";
import FlowNodeToolbar from "@modules/flows/components/FlowNodeToolbar.vue";

interface FlowNodeData {
  id: string | number;
  nodeType: FlowNodeType;
  nodeData: NodeData;
  inputs?: Record<string, { socket: unknown }>;
  outputs?: Record<string, { socket: unknown; label?: string }>;
}

interface FlowContextValue {
  sheetsMap: Record<string, SheetMapEntry>;
  hubsMap: Record<string, HubMapEntry>;
  lod: string;
  nodeDataVersion: number;
  selectedReteNodeId: string | null;
  selectedReteIds: Set<string | number>;
  canEdit: boolean;
  toolbarProps: Record<string, unknown>;
  zoom?: number;
}

const NODE_COMPONENTS: Record<string, Component> = {
  dialogue: DialogueNode,
  entry: EntryNode,
  exit: ExitNode,
  condition: ConditionNode,
  instruction: InstructionNode,
  hub: HubNode,
  jump: JumpNode,
  subflow: SubflowNode,
  annotation: AnnotationNode,
};

const { data, emit: emitFn } = defineProps<{
  data: FlowNodeData;
  emit: (data: { type: string; data: unknown }) => void;
}>();

const ctx = inject<FlowContextValue>(FLOW_CONTEXT_KEY, {
  sheetsMap: {},
  hubsMap: {},
  lod: "full",
  nodeDataVersion: 0,
  selectedReteNodeId: null,
  selectedReteIds: new Set<string | number>(),
  canEdit: false,
  toolbarProps: {},
});

const nodeType = computed(() => data?.nodeType || "dialogue");
const config = computed(() => NODE_CONFIGS[nodeType.value] || NODE_CONFIGS.dialogue);
const nodeComponent = computed(() => NODE_COMPONENTS[nodeType.value] || DialogueNode);

const nodeColor = computed(() => {
  return resolveNodeColor(
    nodeType.value,
    data?.nodeData,
    config.value.color,
    ctx.sheetsMap,
    ctx.hubsMap,
  );
});

const reactiveNodeData = computed(() => {
  void ctx.nodeDataVersion;
  return data?.nodeData || {};
});

const isSelected = computed(() => ctx.selectedReteIds.has(data?.id));

// Toolbar only for a single-node selection. Multi-select or empty selection
// hide it — per-node inline editing doesn't make sense in bulk. Derived from
// the reactive `selectedReteIds` set so it stays in sync across click + marquee
// (unlike the legacy `selectedReteNodeId` which only tracks single click-selects).
const showToolbar = computed(
  () => ctx.canEdit && ctx.selectedReteIds.size === 1 && isSelected.value,
);

const nodeId = computed(() => {
  const reteId = String(data?.id || "");
  return reteId.startsWith("node-") ? reteId.slice(5) : reteId;
});
</script>

<template>
  <div
    class="relative rounded-lg transition-shadow"
    :class="{ 'ring-2 ring-primary ring-offset-2 ring-offset-background': isSelected }"
    style="overflow: visible"
  >
    <FlowNodeToolbar
      v-if="showToolbar"
      :node-type="nodeType"
      :node-data="reactiveNodeData"
      :node-id="nodeId"
      v-bind="ctx.toolbarProps"
    />
    <component
      :is="nodeComponent"
      :data="data"
      :emit="emitFn"
      :config="config"
      :color="nodeColor"
      :sheets-map="ctx.sheetsMap"
      :hubs-map="ctx.hubsMap"
      :node-data-override="reactiveNodeData"
    />
  </div>
</template>
