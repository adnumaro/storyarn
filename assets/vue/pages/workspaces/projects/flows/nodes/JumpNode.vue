<script setup>
import { ArrowRight, LogOut } from "lucide-vue-next";
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
const targetHub = computed(() => {
	const id = nodeData.value.target_hub_id;
	return id ? props.hubsMap[id] : null;
});
const targetLabel = computed(
	() => targetHub.value?.label || nodeData.value.target_hub_id || "",
);
const hasError = computed(() => !nodeData.value.target_hub_id);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="LogOut" :label="config.label">
      <div
        v-if="hasError"
        class="ml-auto inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full bg-destructive text-destructive-foreground"
        title="No target hub"
      >!</div>
    </NodeHeader>
    <div v-if="targetLabel" class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words">
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1">
          <ArrowRight class="size-3" />
          {{ targetLabel }}
        </span>
      </div>
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
