<script setup lang="ts">
import type { Component } from "vue";
import { computed, inject } from "vue";
import type { FlowNodeType, NodeConfig, NodeData } from "../lib/node-configs";
import { NODE_CONFIGS } from "../lib/node-configs";
import { resolveNodeColor } from "../lib/render-helpers";
import type { SheetInfo } from "../lib/render-helpers";
import type { HubMapEntry } from "../types";
import AnnotationNode from "../nodes/AnnotationNode.vue";
import ConditionNode from "../nodes/ConditionNode.vue";
import DialogueNode from "../nodes/DialogueNode.vue";
import EntryNode from "../nodes/EntryNode.vue";
import ExitNode from "../nodes/ExitNode.vue";
import HubNode from "../nodes/HubNode.vue";
import InstructionNode from "../nodes/InstructionNode.vue";
import JumpNode from "../nodes/JumpNode.vue";
import SlugLineNode from "../nodes/SlugLineNode.vue";
import SubflowNode from "../nodes/SubflowNode.vue";
import { FLOW_CONTEXT_KEY } from "../setup";

interface FlowNodeData {
  id: string | number;
  nodeType: FlowNodeType;
  nodeData: NodeData;
  inputs?: Record<string, { socket: unknown }>;
  outputs?: Record<string, { socket: unknown; label?: string }>;
}

interface FlowContextValue {
  sheetsMap: Record<string, SheetInfo>;
  hubsMap: Record<string, HubMapEntry>;
  labels: Record<string, string>;
  lod: string;
  nodeDataVersion: number;
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
  slug_line: SlugLineNode,
  annotation: AnnotationNode,
};

const { data, emit: emitFn } = defineProps<{
  data: FlowNodeData;
  emit: (data: { type: string; data: unknown }) => void;
}>();

const ctx = inject<FlowContextValue>(FLOW_CONTEXT_KEY, {
  sheetsMap: {},
  hubsMap: {},
  labels: {},
  lod: "full",
  nodeDataVersion: 0,
});

const nodeType = computed(() => data?.nodeType || "dialogue");
const config = computed(() => NODE_CONFIGS[nodeType.value] || NODE_CONFIGS.dialogue);
const nodeComponent = computed(() => NODE_COMPONENTS[nodeType.value] || DialogueNode);

// nodeDataVersion from flowContext triggers recomputation when server updates
// nodeData (which is markRaw'd and invisible to Vue reactivity)
const nodeColor = computed(() => {
  const v = ctx.nodeDataVersion;
  return resolveNodeColor(
    nodeType.value,
    data?.nodeData,
    config.value.color,
    ctx.sheetsMap,
    ctx.hubsMap,
  );
});

// Reactive snapshot of nodeData — recomputes when nodeDataVersion bumps
const reactiveNodeData = computed(() => {
  void ctx.nodeDataVersion;
  return data?.nodeData || {};
});
</script>

<template>
  <component
    :is="nodeComponent"
    :data="data"
    :emit="emitFn"
    :config="config"
    :color="nodeColor"
    :sheets-map="ctx.sheetsMap"
    :hubs-map="ctx.hubsMap"
    :labels="ctx.labels"
    :node-data-override="reactiveNodeData"
  />
</template>
