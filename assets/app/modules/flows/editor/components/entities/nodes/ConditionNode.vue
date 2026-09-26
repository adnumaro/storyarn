<script setup lang="ts">
import { GitBranch, TriangleAlert } from "@lucide/vue";
import { Ref } from "rete-vue-plugin";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import NodeHeader from "../node-shell/NodeHeader.vue";
import NodeShell from "../node-shell/NodeShell.vue";
import type { NodeConfig } from "../../../lib/node-configs";
import type {
  Condition,
  ConditionBlock,
  ConditionRule,
  ReteEmitFn,
  ReteNodeData,
} from "../../../../types";
import {
  OPERATOR_LABEL_KEYS,
  type ConditionOperator,
} from "@modules/flows/editor/expression/domain/condition-operators";

interface ConditionNodeData {
  has_stale_refs?: boolean;
  switch_mode?: boolean;
  condition?: Condition;
}

interface OutputBadge {
  type: "error" | "indicator";
  title: string;
  color?: string;
}

const {
  data,
  emit,
  color,
  nodeDataOverride = null,
} = defineProps<{
  data: ReteNodeData;
  emit: ReteEmitFn;
  config: NodeConfig;
  color: string;
  nodeDataOverride?: ConditionNodeData | null;
}>();

const { t } = useI18n();
const nodeData = computed<ConditionNodeData>(
  () => nodeDataOverride || (data.nodeData as ConditionNodeData) || {},
);
const hasStaleRefs = computed(() => nodeData.value.has_stale_refs);

// --- Condition formatting (matching V1 condition.js exactly) ---

// Operators without a symbol read as words, with the same labels as the builder.
const WORD_OPERATORS = new Set<string>(["is_empty", "is_true", "is_false", "is_nil"]);

function getOperatorSymbol(operator: string): string {
  if (WORD_OPERATORS.has(operator)) return t(OPERATOR_LABEL_KEYS[operator as ConditionOperator]);
  const symbols: Record<string, string> = {
    equals: "=",
    not_equals: "≠",
    greater_than: ">",
    greater_than_or_equal: ">=",
    less_than: "<",
    less_than_or_equal: "<=",
    contains: "∋",
    starts_with: "^=",
    ends_with: "$=",
    not_contains: "∌",
    before: "<",
    after: ">",
  };
  return symbols[operator] || operator;
}

function formatRule(rule: ConditionRule): string {
  if (!rule.sheet || !rule.variable) return t("flows.nodes.condition.incomplete_rule");
  const sym = getOperatorSymbol(rule.operator || "");
  const val = rule.value !== null && rule.value !== undefined ? rule.value : "";
  if (["is_empty", "is_true", "is_false", "is_nil"].includes(rule.operator || "")) {
    return `${rule.sheet}.${rule.variable} ${sym}`;
  }
  return `${rule.sheet}.${rule.variable} ${sym} ${val}`;
}

function formatRuleShort(rule: ConditionRule | undefined): string | null {
  if (!rule?.variable) return null;
  const sym = getOperatorSymbol(rule.operator || "");
  const val = rule.value !== null && rule.value !== undefined ? rule.value : "";
  if (["is_empty", "is_true", "is_false", "is_nil"].includes(rule.operator || "")) {
    return `${rule.variable} ${sym}`;
  }
  const strVal = String(val);
  return `${rule.variable} ${sym} ${strVal.length > 10 ? `${strVal.substring(0, 10)}…` : strVal}`;
}

function isRuleComplete(rule: ConditionRule | undefined): boolean {
  if (!rule || !rule.sheet || !rule.variable || !rule.operator) return false;
  const noValueOps = ["is_empty", "is_true", "is_false", "is_nil"];
  if (noValueOps.includes(rule.operator)) return true;
  return rule.value !== null && rule.value !== undefined && rule.value !== "";
}

function countRulesInBlocks(blocks: ConditionBlock[]): number {
  let count = 0;
  for (const b of blocks) {
    if (b.type === "block") count += (b.rules || []).length;
    else if (b.type === "group") count += countRulesInBlocks(b.blocks || []);
  }
  return count;
}

// --- Summary ---

function logicLabel(condition: Condition): string {
  return t(`flows.nodes.condition_summary.${condition.logic === "all" ? "and" : "or"}`);
}

function formatBlockSummary(
  blocks: ConditionBlock[],
  switchMode: boolean,
  condition: Condition,
): string {
  if (blocks.length === 0)
    return t(`flows.nodes.condition_summary.${switchMode ? "no_conditions" : "no_condition"}`);
  if (switchMode) return t("flows.nodes.condition_summary.outputs", blocks.length);
  return t("flows.nodes.condition_summary.rules_in_blocks", {
    rules: t("flows.nodes.condition_summary.rules", countRulesInBlocks(blocks)),
    blocks: t("flows.nodes.condition_summary.blocks", blocks.length),
    logic: logicLabel(condition),
  });
}

function formatFlatSummary(
  rules: ConditionRule[],
  switchMode: boolean,
  condition: Condition,
): string {
  if (switchMode) return t("flows.nodes.condition_summary.outputs", rules.length);
  if (rules.length === 1) return formatRule(rules[0]);
  return t("flows.nodes.condition_summary.rules_with_logic", {
    rules: t("flows.nodes.condition_summary.rules", rules.length),
    logic: logicLabel(condition),
  });
}

const summary = computed(() => {
  const d = nodeData.value;
  const condition = d.condition;

  if (condition?.blocks) {
    return formatBlockSummary(condition.blocks, !!d.switch_mode, condition);
  }
  if (!condition?.rules || condition.rules.length === 0) {
    return t(`flows.nodes.condition_summary.${d.switch_mode ? "no_conditions" : "no_condition"}`);
  }
  return formatFlatSummary(condition.rules, !!d.switch_mode, condition);
});

// --- Sockets ---

const inputs = computed(() => Object.entries(data?.inputs || {}));
const outputs = computed(() => Object.entries(data?.outputs || {}));

function findBlockLabel(blocks: ConditionBlock[], key: string): string {
  const block = blocks.find((b) => b.id === key);
  return block?.label || `Block ${key}`;
}

function findRuleLabel(rules: ConditionRule[], key: string): string {
  const rule = rules.find((r) => r.id === key);
  return rule?.label || formatRuleShort(rule) || key;
}

const BOOLEAN_OUTPUT_LABELS = computed<Record<string, string>>(() => ({
  true: t("flows.nodes.condition.true"),
  false: t("flows.nodes.condition.false"),
}));

function getOutputLabel(key: string): string {
  const d = nodeData.value;
  if (!d.switch_mode) return BOOLEAN_OUTPUT_LABELS.value[key] ?? key;
  if (d.condition?.blocks?.length) return findBlockLabel(d.condition.blocks, key);
  if (d.condition?.rules?.length) return findRuleLabel(d.condition.rules, key);
  return key;
}

function getBlockBadges(blocks: ConditionBlock[], key: string): OutputBadge[] {
  const block = blocks.find((b) => b.id === key);
  if (!block) return [];
  const rules = block.rules || [];
  if (rules.length === 0 || rules.some((r) => !isRuleComplete(r))) {
    return [{ type: "error", title: t("flows.nodes.condition.block_incomplete") }];
  }
  return [];
}

function getRuleBadges(rules: ConditionRule[], key: string): OutputBadge[] {
  const rule = rules.find((r) => r.id === key);
  if (rule && !isRuleComplete(rule)) {
    return [{ type: "error", title: t("flows.nodes.condition.incomplete_rule") }];
  }
  return [];
}

function getOutputBadges(key: string): OutputBadge[] {
  const d = nodeData.value;
  if (!d.switch_mode) return [];

  if (d.condition?.blocks && d.condition.blocks.length > 0) {
    return getBlockBadges(d.condition.blocks, key);
  }
  if (d.condition?.rules && d.condition.rules.length > 0) {
    return getRuleBadges(d.condition.rules, key);
  }
  return [];
}
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="GitBranch" :label="$t('flows.node_types.condition')" />

    <!-- Summary preview -->
    <div
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4]">
        <span v-if="hasStaleRefs" class="inline-flex items-center gap-0.5 text-destructive mr-1">
          <TriangleAlert class="size-3" />
        </span>
        {{ summary }}
      </div>
    </div>

    <!-- Sockets with per-output labels and badges -->
    <div class="py-1">
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
      </div>
      <div
        v-for="[key, output] in outputs"
        :key="'o-' + key"
        class="relative flex items-center py-1 text-[11px] text-muted-foreground justify-end"
      >
        <template v-for="badge in getOutputBadges(key)" :key="badge.title">
          <div
            v-if="badge.type === 'error'"
            class="inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full mr-0.5 bg-destructive text-destructive-foreground cursor-help"
            :title="badge.title"
          >
            !
          </div>
        </template>
        <span class="px-2 max-w-55 wrap-break-word text-right" :title="getOutputLabel(key)">
          {{ getOutputLabel(key) }}
        </span>
        <Ref
          class="output-socket absolute -right-1.5"
          :data="{ type: 'socket', side: 'output', key, nodeId: data.id, payload: output.socket }"
          :emit="emit"
          data-testid="output-socket"
        />
      </div>
    </div>
  </NodeShell>
</template>
