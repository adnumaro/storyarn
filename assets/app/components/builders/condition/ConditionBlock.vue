<script setup lang="ts">
/**
 * Single condition block containing rule rows.
 */

import { Plus, X } from "lucide-vue-next";
import { generateId } from "@modules/shared/variables";
import type { Variable } from "@modules/shared/variables";
import type {
  ConditionBlock as ConditionBlockType,
  ConditionRule as ConditionRuleType,
} from "../types";
import ConditionRule from "./ConditionRule.vue";
import LogicToggle from "./LogicToggle.vue";

const {
  block,
  variables = [],
  disabled = false,
  switchMode = false,
} = defineProps<{
  block: ConditionBlockType;
  variables?: Variable[];
  disabled?: boolean;
  switchMode?: boolean;
}>();

const emit = defineEmits<{
  "update:block": [block: ConditionBlockType];
  remove: [];
}>();

function updateField(field: string, value: string) {
  emit("update:block", { ...block, [field]: value });
}

function updateRule(index: number, updatedRule: ConditionRuleType) {
  const rules = [...block.rules];
  rules[index] = updatedRule;
  emit("update:block", { ...block, rules });
}

function removeRule(index: number) {
  const rules = block.rules.filter((_, i) => i !== index);
  emit("update:block", { ...block, rules });
}

function addRule() {
  const newRule: ConditionRuleType = {
    id: generateId("rule"),
    sheet: null,
    variable: null,
    operator: "equals",
    value: null,
  };
  const rules = [...block.rules, newRule];
  emit("update:block", { ...block, rules });
}
</script>

<template>
  <div class="condition-block rounded-lg border border-border/60 bg-card p-2 group/block">
    <!-- Header: label (switch mode) + remove button -->
    <div class="flex items-center justify-between mb-1">
      <template v-if="switchMode">
        <input
          v-if="!disabled"
          type="text"
          :value="block.label || ''"
          class="h-6 px-2 text-xs font-medium border border-border rounded bg-transparent w-full max-w-50 outline-none focus:border-ring"
          placeholder="label"
          maxlength="100"
          @input="(e: Event) => updateField('label', (e.target as HTMLInputElement).value)"
          @blur="(e: Event) => updateField('label', (e.target as HTMLInputElement).value)"
        />
        <span v-else class="text-xs font-medium">{{ block.label || "label" }}</span>
      </template>
      <span v-else />

      <button
        v-if="!disabled"
        type="button"
        class="inline-flex items-center justify-center size-5 rounded text-muted-foreground hover:text-foreground hover:bg-accent opacity-0 group-hover/block:opacity-100 transition-opacity"
        title="Remove block"
        @click="emit('remove')"
      >
        <X class="size-3" />
      </button>
    </div>

    <!-- Block-level logic toggle -->
    <LogicToggle
      v-if="block.rules.length >= 2 && !switchMode"
      :logic="block.logic"
      of-label="of the rules"
      :disabled="disabled"
      class="mb-1"
      @update:logic="(v) => updateField('logic', v)"
    />

    <!-- Rule rows -->
    <div>
      <ConditionRule
        v-for="(rule, index) in block.rules"
        :key="rule.id"
        :rule="rule"
        :variables="variables"
        :disabled="disabled"
        @update:rule="(r) => updateRule(index, r)"
        @remove="removeRule(index)"
      />
    </div>

    <!-- Add rule button -->
    <button
      v-if="!disabled"
      type="button"
      class="inline-flex items-center justify-center gap-1 w-full mt-1 px-2 py-1 text-xs text-muted-foreground border border-dashed border-border rounded hover:bg-accent/50 transition-colors"
      @click="addRule"
    >
      <Plus class="size-3" />
      Add rule
    </button>

    <p v-if="block.rules.length === 0 && disabled" class="text-xs text-muted-foreground italic">
      No conditions set
    </p>
  </div>
</template>
