<script setup>
import { computed, inject } from "@/vue/index.js";
import { NODE_CONFIGS } from "../lib/node-configs.js";
import { resolveNodeColor } from "../lib/render-helpers.js";
import { FLOW_CONTEXT_KEY } from "../setup.js";

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

const NODE_COMPONENTS = {
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

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
});

const ctx = inject(FLOW_CONTEXT_KEY, { sheetsMap: {}, hubsMap: {}, labels: {}, lod: "full" });

const nodeType = computed(() => props.data?.nodeType || "dialogue");
const config = computed(() => NODE_CONFIGS[nodeType.value] || NODE_CONFIGS.dialogue);
const nodeComponent = computed(() => NODE_COMPONENTS[nodeType.value] || DialogueNode);

// nodeDataVersion from flowContext triggers recomputation when server updates
// nodeData (which is markRaw'd and invisible to Vue reactivity)
const nodeColor = computed(() => {
	const v = ctx.nodeDataVersion;
	console.log("[FlowNode] nodeColor recompute", { nodeType: nodeType.value, version: v, color: props.data?.nodeData?.outcome_color });
	return resolveNodeColor(
		nodeType.value,
		props.data?.nodeData,
		config.value.color,
		ctx.sheetsMap,
		ctx.hubsMap,
	);
});

// Reactive snapshot of nodeData — recomputes when nodeDataVersion bumps
const reactiveNodeData = computed(() => {
	void ctx.nodeDataVersion;
	return props.data?.nodeData || {};
});
</script>

<template>
  <component
    :is="nodeComponent"
    :data="data"
    :emit="emit"
    :config="config"
    :color="nodeColor"
    :sheets-map="ctx.sheetsMap"
    :hubs-map="ctx.hubsMap"
    :labels="ctx.labels"
    :node-data-override="reactiveNodeData"
  />
</template>
