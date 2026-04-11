<script setup lang="ts">
import { ArrowRight, Box, CornerDownLeft, Square } from "lucide-vue-next";
import { Ref } from "rete-vue-plugin";
import { computed } from "vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import type { NodeConfig } from "../lib/node-configs";
import type { ExitLabel, ReteEmitFn, ReteNodeData } from "../types";

interface SubflowNodeData {
  referenced_flow_name?: string;
  referenced_flow_shortcut?: string;
  referenced_flow_id?: number | string | null;
  stale_reference?: boolean;
  exit_labels?: ExitLabel[];
}

const { data, emit, config, color } = defineProps<{
  data: ReteNodeData;
  emit: ReteEmitFn;
  config: NodeConfig;
  color: string;
}>();

const nodeData = computed<SubflowNodeData>(() => (data.nodeData as SubflowNodeData) || {});
const refFlowName = computed(() => nodeData.value.referenced_flow_name);
const refFlowShortcut = computed(() => nodeData.value.referenced_flow_shortcut);
const hasRef = computed(() => !!nodeData.value.referenced_flow_id);
const hasError = computed(() => !hasRef.value || nodeData.value.stale_reference);
const errorTitle = computed(() =>
  nodeData.value.stale_reference ? "Referenced flow was deleted" : "No flow referenced",
);

// Sockets
const inputs = computed(() => Object.entries(data?.inputs || {}));
const outputs = computed(() => Object.entries(data?.outputs || {}));

// Exit labels for dynamic output formatting
const exitLabels = computed<ExitLabel[]>(() => nodeData.value.exit_labels || []);

function getExitInfo(key: string): ExitLabel | null {
  if (!key.startsWith("exit_")) return null;
  const exitId = Number.parseInt(key.replace("exit_", ""), 10);
  return exitLabels.value.find((e) => e.id === exitId) || null;
}
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="Box" :label="config.label">
      <div
        v-if="hasError"
        class="ml-auto inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full bg-destructive text-destructive-foreground"
        :title="errorTitle"
      >
        !
      </div>
    </NodeHeader>

    <!-- Referenced flow name -->
    <div
      v-if="refFlowName"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1">
          <ArrowRight class="size-3" />
          {{ refFlowName }}{{ refFlowShortcut ? ` (#${refFlowShortcut})` : "" }}
        </span>
      </div>
    </div>
    <div
      v-else-if="!hasRef"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4] opacity-50">No flow selected</div>
    </div>

    <!-- Sockets with per-exit labels -->
    <div class="py-1">
      <!-- Inputs -->
      <div
        v-for="[key, input] in inputs"
        :key="'i-' + key"
        class="flex items-center py-1 text-[11px] text-muted-foreground justify-start"
      >
        <Ref
          class="input-socket"
          :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
          :emit="emit"
          data-testid="input-socket"
        />
      </div>
      <!-- Outputs -->
      <div
        v-for="[key, output] in outputs"
        :key="'o-' + key"
        class="flex items-center py-1 text-[11px] text-muted-foreground justify-end"
      >
        <span class="px-2 max-w-55 wrap-break-word text-right inline-flex items-center gap-1">
          <template v-if="getExitInfo(key)">
            <CornerDownLeft
              v-if="getExitInfo(key)!.exit_mode === 'caller_return'"
              class="size-2.5 shrink-0"
            />
            <Square v-else class="size-2.5 shrink-0" />
            {{ getExitInfo(key)!.label || "Exit" }}
          </template>
          <template v-else> Output </template>
        </span>
        <Ref
          class="output-socket"
          :data="{ type: 'socket', side: 'output', key, nodeId: data.id, payload: output.socket }"
          :emit="emit"
          data-testid="output-socket"
        />
      </div>
    </div>
  </NodeShell>
</template>
