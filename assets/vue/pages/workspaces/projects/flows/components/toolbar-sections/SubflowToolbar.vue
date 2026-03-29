<script setup>
import { Box, ExternalLink } from "lucide-vue-next";
import { computed } from "vue";
import { ToolbarSeparator } from "@/vue/components/shared/toolbar/index.js";
import { Badge } from "@/vue/components/ui/badge/index.js";
import { useLive } from "@/vue/composables/useLive.js";
import { ToolbarSearchableSelect } from "../../toolbar/index.js";

const props = defineProps({
	nodeData: { type: Object, required: true },
	availableFlows: { type: Array, default: () => [] },
	subflowExits: { type: Array, default: () => [] },
});

const live = useLive();

const flowOptions = computed(() =>
	props.availableFlows.map((f) => [f.name, f.id]),
);

const selectedFlowName = computed(() => {
	const refId = props.nodeData.referenced_flow_id;
	if (!refId) return null;
	const flow = props.availableFlows.find((f) => String(f.id) === String(refId));
	return flow?.name || null;
});

function selectSubflowRef(flowId) {
	live.pushEvent("update_subflow_reference", { referenced_flow_id: flowId });
}

function navigateToSubflow(flowId) {
	live.pushEvent("navigate_to_subflow", { "flow-id": String(flowId) });
}
</script>

<template>
  <component :is="Box" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <ToolbarSearchableSelect
    :options="flowOptions"
    :selected-value="nodeData.referenced_flow_id"
    :selected-label="selectedFlowName"
    placeholder="Select flow…"
    @select="selectSubflowRef"
  />
  <button
    v-if="nodeData.referenced_flow_id"
    type="button"
    class="v2-toolbar-btn"
    title="Open flow"
    @click="navigateToSubflow(nodeData.referenced_flow_id)"
  >
    <ExternalLink class="size-3.5" />
  </button>
  <Badge v-if="subflowExits.length > 0" variant="secondary" class="text-[10px] px-1.5 py-0 rounded-full">
    {{ subflowExits.length }} exit{{ subflowExits.length === 1 ? '' : 's' }}
  </Badge>
</template>
