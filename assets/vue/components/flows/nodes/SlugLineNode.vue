<script setup>
import { computed } from "vue";
import { previewText } from "../lib/render-helpers.js";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
	sheetsMap: { type: Object, default: () => ({}) },
});

const nodeData = computed(() => props.data.nodeData || {});

const locationName = computed(() => {
	const sheetId = nodeData.value.location_sheet_id;
	if (!sheetId) return null;
	return props.sheetsMap[String(sheetId)]?.name;
});

const headerLabel = computed(() => locationName.value || props.config.label);

const slugLine = computed(() => {
	const d = nodeData.value;
	const parts = [];
	if (d.int_ext) parts.push(`${d.int_ext.replace("_", "/").toUpperCase()}.`);
	if (d.sub_location) parts.push(d.sub_location.toUpperCase());
	if (d.time_of_day) {
		if (parts.length > 0) parts.push("-");
		parts.push(d.time_of_day.toUpperCase());
	}
	return parts.length > 0 ? parts.join(" ") : null;
});

const description = computed(() => previewText(nodeData.value.description));
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="config.icon" :label="headerLabel" />
    <div v-if="slugLine" class="text-[10px] font-mono font-bold text-muted-foreground px-3 py-1.5 uppercase tracking-wider border-b border-border/30">
      {{ slugLine }}
    </div>
    <div v-if="description" class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/30 break-words">
      <div class="line-clamp-4 leading-[1.4]">{{ description }}</div>
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
