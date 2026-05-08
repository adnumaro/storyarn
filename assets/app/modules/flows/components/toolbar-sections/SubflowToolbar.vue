<script setup lang="ts">
import { Box, ExternalLink } from "lucide-vue-next";
import { computed } from "vue";
import { ToolbarSeparator } from "@components/toolbar/index.ts";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Badge } from "@components/ui/badge/index.ts";
import { useLive } from "../../../../shared/composables/useLive";
import { ToolbarSearchableSelect } from "../../toolbar";
import type { ProjectFlow, SubflowExit } from "../../types";
import type { NodeData } from "../../lib/node-configs";

defineOptions({ inheritAttrs: false });

interface SubflowToolbarData extends NodeData {
  referenced_flow_id?: number | string | null;
}

const {
  nodeData,
  projectFlows = [],
  subflowExits = [],
} = defineProps<{
  nodeData: SubflowToolbarData;
  projectFlows?: ProjectFlow[];
  subflowExits?: SubflowExit[];
}>();

const live = useLive();

const flowOptions = computed<[string, number][]>(() => projectFlows.map((f) => [f.name, f.id]));

const selectedFlowName = computed(() => {
  const refId = nodeData.referenced_flow_id;
  if (!refId) return null;
  const flow = projectFlows.find((f) => String(f.id) === String(refId));
  return flow?.name || null;
});

function selectSubflowRef(flowId: number | string) {
  live.pushEvent("update_subflow_reference", { referenced_flow_id: flowId });
}

function navigateToSubflow(flowId: number | string) {
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
    :placeholder="$t('flows.subflow_toolbar.select_flow_placeholder')"
    @select="selectSubflowRef"
  />
  <ToolbarTooltip v-if="nodeData.referenced_flow_id" :label="$t('flows.subflow_toolbar.open_flow')">
    <button
      type="button"
      class="toolbar-btn"
      @click="navigateToSubflow(nodeData.referenced_flow_id!)"
    >
      <ExternalLink class="size-3.5" />
    </button>
  </ToolbarTooltip>
  <Badge
    v-if="subflowExits.length > 0"
    variant="secondary"
    class="text-[10px] px-1.5 py-0 rounded-full"
  >
    {{ subflowExits.length }} exit{{ subflowExits.length === 1 ? "" : "s" }}
  </Badge>
</template>
