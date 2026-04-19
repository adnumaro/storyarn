<script setup lang="ts">
import { ArrowUpRight, LogIn } from "lucide-vue-next";
import { computed } from "vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";
import type { NodeConfig } from "../lib/node-configs";
import type { HubMapEntry, ReteEmitFn, ReteNodeData } from "../types";

interface HubNodeData {
  hub_id?: string;
}

const {
  data,
  emit,
  config,
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
  return hubId && hubsMap[hubId] ? hubsMap[hubId].jumpCount : 0;
});
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="LogIn" :label="config.label" />
    <div
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1">
          <ArrowUpRight class="size-3" />
          {{ jumpCount }} jump{{ jumpCount !== 1 ? "s" : "" }}
        </span>
      </div>
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
