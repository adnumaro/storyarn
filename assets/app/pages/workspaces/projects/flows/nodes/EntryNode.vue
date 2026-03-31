<script setup>
import { Box, Play, Square } from "lucide-vue-next";
import { computed } from "vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";

const props = defineProps({
  data: { type: Object, required: true },
  emit: { type: Function, required: true },
  config: { type: Object, required: true },
  color: { type: String, required: true },
});

const refs = computed(() => props.data.nodeData?.referencing_flows || []);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="Play" :label="config.label" />
    <div
      v-for="ref in refs"
      :key="ref.flow_id"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words"
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
