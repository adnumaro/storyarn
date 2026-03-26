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
const exitMode = computed(() => nodeData.value.exit_mode || "terminal");
const label = computed(() => nodeData.value.label || props.config.label);
const tags = computed(() => nodeData.value.outcome_tags || []);
const refFlowName = computed(() => nodeData.value.referenced_flow_name);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="config.icon" :label="label" />
    <div v-if="refFlowName && exitMode === 'flow_reference'" class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/30 break-words">
      <span class="line-clamp-4 leading-[1.4]">→ {{ refFlowName }}</span>
    </div>
    <div v-if="tags.length > 0" class="text-[10px] text-muted-foreground px-3 py-1 border-b border-border/30">
      {{ tags.slice(0, 3).join(', ') }}{{ tags.length > 3 ? ` +${tags.length - 3} more` : '' }}
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
