<script setup lang="ts">
import { ArrowRight, ArrowRightToLine, CornerDownLeft } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import NodeHeader from "../node-shell/NodeHeader.vue";
import NodeShell from "../node-shell/NodeShell.vue";
import NodeSockets from "../node-shell/NodeSockets.vue";
import type { NodeConfig } from "../../../lib/node-configs";
import type { ReteEmitFn, ReteNodeData } from "../../../../types";

interface ExitNodeData {
  exit_mode?: string;
  label?: string;
  outcome_tags?: string[];
  referenced_flow_name?: string;
  referenced_flow_shortcut?: string;
  referenced_flow_id?: number | string | null;
  stale_reference?: boolean;
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
  nodeDataOverride?: ExitNodeData | null;
}>();

const { t } = useI18n();
const nodeData = computed<ExitNodeData>(
  () => nodeDataOverride || (data.nodeData as ExitNodeData) || {},
);
const exitMode = computed(() => nodeData.value.exit_mode || "terminal");
const label = computed(() => nodeData.value.label || "Exit");
const tags = computed(() => nodeData.value.outcome_tags || []);
const refFlowName = computed(() => nodeData.value.referenced_flow_name);
const refFlowShortcut = computed(() => nodeData.value.referenced_flow_shortcut);

// Error indicators
const hasError = computed(() => {
  if (exitMode.value === "flow_reference" && !nodeData.value.referenced_flow_id) return true;
  return !!nodeData.value.stale_reference;
});
const errorTitle = computed(() =>
  nodeData.value.stale_reference
    ? t("flows.nodes.exit.flow_deleted")
    : t("flows.nodes.exit.no_flow"),
);

// Tags text
const tagsText = computed(() => {
  if (tags.value.length === 0) return "";
  if (tags.value.length > 3)
    return `${tags.value.slice(0, 3).join(", ")} +${tags.value.length - 3}`;
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
      >
        !
      </div>
    </NodeHeader>

    <!-- Preview: label + exit mode icon -->
    <div
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1">
          {{ label }}
          <CornerDownLeft v-if="exitMode === 'caller_return'" class="size-3" />
          <ArrowRight v-else-if="exitMode === 'flow_reference'" class="size-3" />
          <ArrowRightToLine v-else class="size-3" />
        </span>
      </div>
    </div>

    <!-- Flow reference nav link -->
    <div
      v-if="exitMode === 'flow_reference' && refFlowName"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4]">
        <span class="inline-flex items-center gap-1">
          <ArrowRight class="size-3" />
          {{ refFlowName }}{{ refFlowShortcut ? ` (#${refFlowShortcut})` : "" }}
        </span>
      </div>
    </div>

    <!-- Outcome tags -->
    <div
      v-if="tagsText"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4] opacity-60 text-[0.7em]">
        {{ tagsText }}
      </div>
    </div>

    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
