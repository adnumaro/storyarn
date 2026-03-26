<script setup>
import { computed } from "vue";
import { formatAssignment } from "../lib/render-helpers.js";
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

const summary = computed(() => {
	const assignments = nodeData.value.assignments || [];
	if (assignments.length === 0) return "No assignments";
	return assignments
		.slice(0, 3)
		.map(formatAssignment)
		.join("\n");
});

const hasWarnings = computed(() =>
	nodeData.value.has_stale_refs || nodeData.value.has_type_warnings,
);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="config.icon" :label="config.label" />
    <div class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/30 break-words">
      <div class="line-clamp-4 leading-[1.4] whitespace-pre-line">
        <span v-if="hasWarnings" class="text-destructive mr-1">⚠</span>
        {{ summary }}
      </div>
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
