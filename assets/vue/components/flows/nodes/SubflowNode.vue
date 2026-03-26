<script setup>
import { computed } from "vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
});

const nodeData = computed(() => props.data.nodeData || {});
const refFlowName = computed(() => nodeData.value.referenced_flow_name);
const refFlowShortcut = computed(() => nodeData.value.referenced_flow_shortcut);
const hasRef = computed(() => !!nodeData.value.referenced_flow_id);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="config.icon" :label="config.label" />
    <div v-if="refFlowName" class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/30 break-words">
      <span class="line-clamp-4 leading-[1.4]">
        → {{ refFlowName }}{{ refFlowShortcut ? ` (#${refFlowShortcut})` : '' }}
      </span>
    </div>
    <div v-else-if="!hasRef" class="text-[11px] text-muted-foreground/50 px-3 py-2 border-b border-border/30">
      No flow selected
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
