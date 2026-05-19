<script setup lang="ts">
import { ArrowRight, Box, CornerDownLeft, Square } from "lucide-vue-next";
import { Ref } from "rete-vue-plugin";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import NodeHeader from "../node-shell/NodeHeader.vue";
import NodeShell from "../node-shell/NodeShell.vue";
import type { NodeConfig } from "../../../lib/node-configs";
import type { ExitLabel, ReteEmitFn, ReteNodeData } from "../../../../types";

interface SubflowNodeData {
  referenced_flow_name?: string;
  referenced_flow_shortcut?: string;
  referenced_flow_id?: number | string | null;
  stale_reference?: boolean;
  exit_labels?: ExitLabel[];
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
  nodeDataOverride?: SubflowNodeData | null;
}>();

const { t } = useI18n();
const nodeData = computed<SubflowNodeData>(
  () => nodeDataOverride || (data.nodeData as SubflowNodeData) || {},
);
const refFlowName = computed(() => nodeData.value.referenced_flow_name);
const refFlowShortcut = computed(() => nodeData.value.referenced_flow_shortcut);
const hasRef = computed(() => !!nodeData.value.referenced_flow_id);
const hasError = computed(() => !hasRef.value || nodeData.value.stale_reference);
const errorTitle = computed(() =>
  nodeData.value.stale_reference
    ? t("flows.nodes.subflow.flow_deleted")
    : t("flows.nodes.subflow.no_flow_ref"),
);

// Sockets
const inputs = computed(() => Object.entries(data?.inputs || {}));
const outputs = computed(() => Object.entries(data?.outputs || {}));
const usesSingleOutputRow = computed(() => inputs.value.length === 1 && outputs.value.length === 1);

// Exit labels for dynamic output formatting
const exitLabels = computed<ExitLabel[]>(() => nodeData.value.exit_labels || []);

function getExitInfo(key: string): ExitLabel | null {
  if (!key.startsWith("exit_")) return null;
  const exitId = Number.parseInt(key.replace("exit_", ""), 10);
  return exitLabels.value.find((e) => e.id === exitId) || null;
}

function outputLabel(key: string): string {
  const exitInfo = getExitInfo(key);
  return exitInfo ? exitInfo.label || "Exit" : key;
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
      <div class="line-clamp-4 leading-[1.4] opacity-50">
        {{ t("flows.nodes.subflow.no_flow") }}
      </div>
    </div>

    <!-- Sockets with per-exit labels -->
    <div class="py-1">
      <template v-if="usesSingleOutputRow">
        <div class="sockets-row relative flex justify-between items-center py-1">
          <template v-for="[key, input] in inputs" :key="'i-' + key">
            <Ref
              class="input-socket absolute -left-1.5"
              :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
              :emit="emit"
              data-testid="input-socket"
            />
            <span class="text-[11px] text-muted-foreground ml-2">{{ key }}</span>
          </template>
          <span class="flex-1" />
          <template v-for="[key, output] in outputs" :key="'o-' + key">
            <span class="text-[11px] text-muted-foreground mr-2">{{ outputLabel(key) }}</span>
            <Ref
              class="output-socket absolute -right-1.5"
              :data="{
                type: 'socket',
                side: 'output',
                key,
                nodeId: data.id,
                payload: output.socket,
              }"
              :emit="emit"
              data-testid="output-socket"
            />
          </template>
        </div>
      </template>
      <template v-else>
        <!-- Inputs -->
        <div
          v-for="[key, input] in inputs"
          :key="'i-' + key"
          class="relative flex items-center py-1 text-[11px] text-muted-foreground justify-start"
        >
          <Ref
            class="input-socket absolute -left-1.5"
            :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
            :emit="emit"
            data-testid="input-socket"
          />
          <span class="ml-2">{{ key }}</span>
        </div>
        <!-- Outputs -->
        <div
          v-for="[key, output] in outputs"
          :key="'o-' + key"
          class="relative flex items-center py-1 text-[11px] text-muted-foreground justify-end"
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
            <template v-else>{{ key }}</template>
          </span>
          <Ref
            class="output-socket absolute -right-1.5"
            :data="{ type: 'socket', side: 'output', key, nodeId: data.id, payload: output.socket }"
            :emit="emit"
            data-testid="output-socket"
          />
        </div>
      </template>
    </div>
  </NodeShell>
</template>
