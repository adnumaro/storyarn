<script setup lang="ts">
import { TriangleAlert, Zap } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";
import type { NodeConfig } from "../lib/node-configs";
import type { InstructionAssignment, ReteEmitFn, ReteNodeData } from "../types";

interface InstructionNodeData {
  assignments?: InstructionAssignment[];
  has_stale_refs?: boolean;
  has_type_warnings?: boolean;
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
  nodeDataOverride?: InstructionNodeData | null;
}>();

const { t } = useI18n();
const nodeData = computed<InstructionNodeData>(
  () => nodeDataOverride || (data.nodeData as InstructionNodeData) || {},
);

// --- Formatting (matching V1 instruction.js exactly) ---

function getBooleanOpString(op: string, ref: string): string | null {
  const map: Record<string, string> = {
    set_true: t("flows.nodes.instruction.set_true", { var: ref }),
    set_false: t("flows.nodes.instruction.set_false", { var: ref }),
    toggle: t("flows.nodes.instruction.toggle", { var: ref }),
    clear: t("flows.nodes.instruction.clear", { var: ref }),
  };
  return map[op] || null;
}

function getValueDisplay(assignment: InstructionAssignment): string {
  if (assignment.value_type === "variable_ref" && assignment.value_sheet && assignment.value) {
    return `${assignment.value_sheet}.${assignment.value}`;
  }
  return String(assignment.value || "?");
}

function getValueOpString(op: string, ref: string, val: string): string {
  const map: Record<string, string> = {
    add: t("flows.nodes.instruction.add", { value: val, var: ref }),
    subtract: t("flows.nodes.instruction.subtract", { value: val, var: ref }),
  };
  return map[op] || `${ref} = ${val}`;
}

function formatAssignment(assignment: InstructionAssignment): string | null {
  if (!assignment.sheet || !assignment.variable) return null;
  const ref = `${assignment.sheet}.${assignment.variable}`;
  const op = assignment.operator || "set";

  const boolStr = getBooleanOpString(op, ref);
  if (boolStr) return boolStr;

  return getValueOpString(op, ref, getValueDisplay(assignment));
}

const summary = computed(() => {
  const assignments = nodeData.value.assignments || [];
  if (assignments.length === 0) return "";
  return assignments.slice(0, 3).map(formatAssignment).filter(Boolean).join("\n");
});

const hasWarnings = computed(
  () => nodeData.value.has_stale_refs || nodeData.value.has_type_warnings,
);
const hasStaleRefs = computed(() => nodeData.value.has_stale_refs);
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="Zap" :label="config.label">
      <div
        v-if="hasWarnings"
        class="ml-auto inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full bg-destructive text-destructive-foreground"
        :title="t('flows.nodes.instruction.type_mismatch')"
      >
        !
      </div>
    </NodeHeader>

    <div
      v-if="summary || hasStaleRefs"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4] whitespace-pre-line">
        <span v-if="hasStaleRefs" class="inline-flex items-center gap-0.5 text-destructive mr-1">
          <TriangleAlert class="size-3" />
        </span>
        {{ summary || t("flows.nodes.instruction.stale_references") }}
      </div>
    </div>

    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
