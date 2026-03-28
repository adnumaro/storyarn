<script setup>
import { computed } from "vue";
import { ArrowRight, ArrowRightToLine, CornerDownLeft } from "lucide-vue-next";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
	nodeDataOverride: { type: Object, default: null },
});

const nodeData = computed(() => props.nodeDataOverride || props.data.nodeData || {});
const exitMode = computed(() => nodeData.value.exit_mode || "terminal");
const label = computed(() => nodeData.value.label || "Exit");
const tags = computed(() => nodeData.value.outcome_tags || []);
const refFlowName = computed(() => nodeData.value.referenced_flow_name);
const refFlowShortcut = computed(() => nodeData.value.referenced_flow_shortcut);

// Error indicators
const hasError = computed(() => {
	if (exitMode.value === "flow_reference" && !nodeData.value.referenced_flow_id) return true;
	if (nodeData.value.stale_reference) return true;
	return false;
});
const errorTitle = computed(() =>
	nodeData.value.stale_reference ? "Referenced flow was deleted" : "No flow referenced",
);

// Tags text
const tagsText = computed(() => {
	if (tags.value.length === 0) return "";
	if (tags.value.length > 3) return `${tags.value.slice(0, 3).join(", ")} +${tags.value.length - 3}`;
	return tags.value.join(", ");
});
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="ArrowRightToLine" :label="config.label">
      <div
        v-if="hasError"
        class="ml-auto inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full bg-destructive text-destructive-foreground"
        :title="errorTitle"
      >!</div>
    </NodeHeader>

    <!-- Preview: label + exit mode icon -->
    <div class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words">
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1">
          {{ label }}
          <CornerDownLeft v-if="exitMode === 'caller_return'" class="size-3" />
          <ArrowRightToLine v-else-if="exitMode !== 'flow_reference'" class="size-3" />
        </span>
      </div>
    </div>

    <!-- Flow reference nav link -->
    <div
      v-if="exitMode === 'flow_reference' && refFlowName"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words"
    >
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1">
          <ArrowRight class="size-3" />
          {{ refFlowName }}{{ refFlowShortcut ? ` (#${refFlowShortcut})` : '' }}
        </span>
      </div>
    </div>

    <!-- Outcome tags -->
    <div v-if="tagsText" class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words">
      <div class="line-clamp-4 leading-[1.4] opacity-60 text-[0.7em]">
        {{ tagsText }}
      </div>
    </div>

    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
