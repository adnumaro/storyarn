<script setup>
import { computed } from "vue";
import { formatRule } from "../lib/render-helpers.js";
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
	const d = nodeData.value;
	const condition = d.condition || {};
	const rules = condition.rules || [];
	const blocks = condition.blocks || [];
	const switchMode = d.switch_mode || false;

	if (switchMode) {
		if (blocks.length > 0) {
			return `${blocks.length} output${blocks.length !== 1 ? "s" : ""} + default`;
		}
		return `${rules.length} output${rules.length !== 1 ? "s" : ""} + default`;
	}

	if (rules.length === 0) return "No conditions";
	if (rules.length === 1) return formatRule(rules[0]);

	const logic = condition.logic || "all";
	const join = logic === "all" ? "AND" : "OR";
	return `${rules.length} rules (${join})`;
});

const hasStaleRefs = computed(() => nodeData.value.has_stale_refs);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="config.icon" :label="config.label" />
    <div class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/30 break-words">
      <div class="line-clamp-4 leading-[1.4]">
        <span v-if="hasStaleRefs" class="text-destructive mr-1">⚠</span>
        {{ summary }}
      </div>
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
