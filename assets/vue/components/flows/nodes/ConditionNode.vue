<script setup>
import { computed } from "vue";
import { GitBranch, TriangleAlert } from "lucide-vue-next";
import { Ref } from "rete-vue-plugin";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
});

const nodeData = computed(() => props.data.nodeData || {});
const hasStaleRefs = computed(() => nodeData.value.has_stale_refs);

// --- Condition formatting (matching V1 condition.js exactly) ---

function getOperatorSymbol(operator) {
	const symbols = {
		equals: "=", not_equals: "≠", greater_than: ">", greater_than_or_equal: ">=",
		less_than: "<", less_than_or_equal: "<=", contains: "∋", starts_with: "^=",
		ends_with: "$=", is_empty: "is empty", is_true: "is true", is_false: "is false",
		is_nil: "is nil", not_contains: "∌", before: "<", after: ">",
	};
	return symbols[operator] || operator;
}

function formatRule(rule) {
	if (!rule.sheet || !rule.variable) return "Incomplete rule";
	const sym = getOperatorSymbol(rule.operator);
	const val = rule.value !== null && rule.value !== undefined ? rule.value : "";
	if (["is_empty", "is_true", "is_false", "is_nil"].includes(rule.operator)) {
		return `${rule.sheet}.${rule.variable} ${sym}`;
	}
	return `${rule.sheet}.${rule.variable} ${sym} ${val}`;
}

function formatRuleShort(rule) {
	if (!rule?.variable) return null;
	const sym = getOperatorSymbol(rule.operator);
	const val = rule.value !== null && rule.value !== undefined ? rule.value : "";
	if (["is_empty", "is_true", "is_false", "is_nil"].includes(rule.operator)) {
		return `${rule.variable} ${sym}`;
	}
	const strVal = String(val);
	return `${rule.variable} ${sym} ${strVal.length > 10 ? `${strVal.substring(0, 10)}…` : strVal}`;
}

function isRuleComplete(rule) {
	if (!rule) return false;
	const hasSheet = rule.sheet && rule.sheet !== "";
	const hasVariable = rule.variable && rule.variable !== "";
	const hasOperator = rule.operator && rule.operator !== "";
	const noValueOps = ["is_empty", "is_true", "is_false", "is_nil"];
	const needsValue = !noValueOps.includes(rule.operator);
	const hasValue = !needsValue || (rule.value !== null && rule.value !== undefined && rule.value !== "");
	return hasSheet && hasVariable && hasOperator && hasValue;
}

function countRulesInBlocks(blocks) {
	let count = 0;
	for (const b of blocks) {
		if (b.type === "block") count += (b.rules || []).length;
		else if (b.type === "group") count += countRulesInBlocks(b.blocks || []);
	}
	return count;
}

// --- Summary ---

const summary = computed(() => {
	const d = nodeData.value;
	const condition = d.condition;
	const switchMode = d.switch_mode;

	// Block format
	if (condition?.blocks) {
		const blocks = condition.blocks;
		if (blocks.length === 0) return switchMode ? "No conditions" : "No condition";
		if (switchMode) return `${blocks.length} output${blocks.length > 1 ? "s" : ""} + default`;
		const ruleCount = countRulesInBlocks(blocks);
		const logic = condition.logic === "all" ? "AND" : "OR";
		return `${ruleCount} rule${ruleCount !== 1 ? "s" : ""} in ${blocks.length} block${blocks.length !== 1 ? "s" : ""} (${logic})`;
	}

	// Flat format
	if (!condition?.rules || condition.rules.length === 0) {
		return switchMode ? "No conditions" : "No condition";
	}
	const rules = condition.rules;
	if (switchMode) return `${rules.length} output${rules.length > 1 ? "s" : ""} + default`;
	const logic = condition.logic === "all" ? "AND" : "OR";
	if (rules.length === 1) return formatRule(rules[0]);
	return `${rules.length} rules (${logic})`;
});

// --- Sockets ---

const inputs = computed(() => Object.entries(props.data?.inputs || {}));
const outputs = computed(() => Object.entries(props.data?.outputs || {}));

function getOutputLabel(key) {
	const d = nodeData.value;
	if (d.switch_mode) {
		if (key === "default") return "Default";
		if (d.condition?.blocks?.length > 0) {
			const block = d.condition.blocks.find((b) => b.id === key);
			if (block) return block.label || `Block ${key}`;
			return key;
		}
		if (d.condition?.rules?.length > 0) {
			const rule = d.condition.rules.find((r) => r.id === key);
			return rule?.label || formatRuleShort(rule) || key;
		}
	}
	return key === "true" ? "True" : key === "false" ? "False" : key;
}

function getOutputBadges(key) {
	const d = nodeData.value;
	const badges = [];
	if (d.switch_mode && key !== "default") {
		if (d.condition?.blocks?.length > 0) {
			const block = d.condition.blocks.find((b) => b.id === key);
			if (block) {
				const rules = block.rules || [];
				if (rules.length === 0 || rules.some((r) => !isRuleComplete(r))) {
					badges.push({ type: "error", title: "Block has incomplete rules" });
				}
			}
		} else if (d.condition?.rules?.length > 0) {
			const rule = d.condition.rules.find((r) => r.id === key);
			if (rule && !isRuleComplete(rule)) {
				badges.push({ type: "error", title: "Incomplete rule" });
			}
		}
	}
	return badges;
}
</script>

<template>
  <NodeShell :color="color" :selected="data.selected">
    <NodeHeader :color="color" :icon="GitBranch" :label="config.label" />

    <!-- Summary preview -->
    <div class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words">
      <div class="line-clamp-4 leading-[1.4]">
        <span v-if="hasStaleRefs" class="inline-flex items-center gap-0.5 text-destructive mr-1">
          <TriangleAlert class="size-3" />
        </span>
        {{ summary }}
      </div>
    </div>

    <!-- Sockets with per-output labels and badges -->
    <div class="py-1">
      <div v-for="[key, input] in inputs" :key="'i-' + key" class="flex items-center py-1 text-[11px] text-muted-foreground justify-start">
        <Ref
          class="input-socket"
          :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
          :emit="emit"
          data-testid="input-socket"
        />
      </div>
      <div v-for="[key, output] in outputs" :key="'o-' + key" class="flex items-center py-1 text-[11px] text-muted-foreground justify-end">
        <template v-for="badge in getOutputBadges(key)" :key="badge.title">
          <div
            v-if="badge.type === 'error'"
            class="inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full mr-0.5 bg-destructive text-destructive-foreground cursor-help"
            :title="badge.title"
          >!</div>
        </template>
        <span class="px-2 max-w-[220px] break-words text-right" :title="getOutputLabel(key)">
          {{ getOutputLabel(key) }}
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
