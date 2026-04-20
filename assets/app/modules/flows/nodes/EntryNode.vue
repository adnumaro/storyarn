<script setup lang="ts">
import { Box, Play, Square } from "lucide-vue-next";
import { computed } from "vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";
import type { NodeConfig } from "../lib/node-configs";
import type { ReferencingFlow, ReteEmitFn, ReteNodeData } from "../types";

interface EntryNodeData {
  referencing_flows?: ReferencingFlow[];
}

const {
  data,
  emit,
  config,
  color,
  nodeDataOverride = null,
} = defineProps<{
  data: ReteNodeData;
  emit: ReteEmitFn;
  config: NodeConfig;
  color: string;
  nodeDataOverride?: EntryNodeData | null;
}>();

const nodeData = computed<EntryNodeData>(
  () => nodeDataOverride || (data.nodeData as EntryNodeData) || {},
);
const refs = computed<ReferencingFlow[]>(() => nodeData.value.referencing_flows || []);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="Play" :label="config.label" />
    <div
      v-for="ref in refs"
      :key="ref.flow_id"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1 align-middle">
          <Square v-if="ref.node_type === 'exit'" class="size-3 shrink-0" />
          <Box v-else class="size-3 shrink-0" />
          {{ ref.flow_name }}{{ ref.flow_shortcut ? ` (#${ref.flow_shortcut})` : "" }}
        </span>
      </div>
    </div>
    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
