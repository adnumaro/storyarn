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
	hubsMap: { type: Object, default: () => ({}) },
});

const nodeData = computed(() => props.data.nodeData || {});
const jumpCount = computed(() => {
	const hubId = nodeData.value.hub_id;
	return hubId && props.hubsMap[hubId] ? props.hubsMap[hubId].jumpCount : 0;
});
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="config.icon" :label="config.label" />
    <div v-if="jumpCount > 0" class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/30">
      → {{ jumpCount }} jump{{ jumpCount !== 1 ? 's' : '' }}
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
