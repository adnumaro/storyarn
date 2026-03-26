<script setup>
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
});

const refs = (props.data.nodeData?.referencing_flows || []);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="config.icon" :label="config.label" />
    <div
      v-for="ref in refs"
      :key="ref.flow_id"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/30 break-words"
    >
      <span class="line-clamp-4 leading-[1.4]">
        {{ ref.flow_name }}{{ ref.flow_shortcut ? ` (#${ref.flow_shortcut})` : '' }}
      </span>
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
