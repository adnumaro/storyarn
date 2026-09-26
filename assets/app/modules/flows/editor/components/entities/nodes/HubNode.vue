<script setup lang="ts">
import { ArrowUpRight, LogIn } from "@lucide/vue";
import { computed } from "vue";
import NodeHeader from "../node-shell/NodeHeader.vue";
import NodeShell from "../node-shell/NodeShell.vue";
import NodeSockets from "../node-shell/NodeSockets.vue";
import type { NodeConfig } from "../../../lib/node-configs";
import type { HubMapEntry, ReteEmitFn, ReteNodeData } from "../../../../types";

interface HubNodeData {
  hub_id?: string;
}

const {
  data,
  emit,
  color,
  hubsMap = {},
  nodeDataOverride = null,
} = defineProps<{
  data: ReteNodeData;
  emit: ReteEmitFn;
  config: NodeConfig;
  color: string;
  hubsMap?: Record<string, HubMapEntry>;
  nodeDataOverride?: HubNodeData | null;
}>();

const nodeData = computed<HubNodeData>(
  () => nodeDataOverride || (data.nodeData as HubNodeData) || {},
);
const jumpCount = computed(() => {
  const hubId = nodeData.value.hub_id;
  return (hubId && hubsMap[hubId]?.jumpCount) || 0;
});
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="LogIn" :label="$t('flows.node_types.hub')" />
    <div
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1">
          <ArrowUpRight class="size-3" />
          {{ $t("flows.nodes.hub_jumps", jumpCount) }}
        </span>
      </div>
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
