<script setup lang="ts">
/**
 * Single condition rule row — sentence-flow layout.
 *
 * Uses .condition-rule-row and .sentence-text/.sentence-slot CSS classes.
 */

import { X } from "lucide-vue-next";
import { computed } from "vue";
import {
  NO_VALUE_OPERATORS,
  OPERATOR_LABELS,
  operatorsForType,
} from "@modules/shared/operators/condition-operators";
import type { ConditionOperator } from "@modules/shared/operators/condition-operators";
import { findVariable, groupVariablesBySheet } from "@modules/shared/variables";
import type { Variable } from "@modules/shared/variables";
import type { ConditionRule } from "../types";
import VariableCombobox from "../../VariableCombobox.vue";

const {
  rule,
  variables = [],
  disabled = false,
} = defineProps<{
  rule: ConditionRule;
  variables?: Variable[];
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:rule": [rule: ConditionRule];
  remove: [];
}>();

const sheetsWithVariables = computed(() => groupVariablesBySheet(variables));

const sheetOptions = computed(() =>
  sheetsWithVariables.value.map((s) => ({ value: s.shortcut, label: s.name })),
);

const variableGroups = computed(() => {
  if (!rule.sheet) return [];
  const sheet = sheetsWithVariables.value.find((s) => s.shortcut === rule.sheet);
  if (!sheet) return [];
  return [
    {
      heading: sheet.name,
      items: sheet.vars.map((v) => ({
        value: v.variable_name,
        label: v.variable_name,
      })),
    },
  ];
});

const variableType = computed(() => {
  const v = findVariable(variables, rule.sheet, rule.variable);
  return v ? v.block_type : null;
});

const operatorOptions = computed(() => {
  if (!variableType.value) return [];
  return operatorsForType(variableType.value).map((op) => ({
    value: op,
    label: OPERATOR_LABELS[op] || op,
  }));
});

const needsValue = computed(() => rule.operator && !NO_VALUE_OPERATORS.has(rule.operator));

const valueOptions = computed(() => {
  const v = findVariable(variables, rule.sheet, rule.variable);
  if (v && (v.block_type === "select" || v.block_type === "multi_select") && v.options) {
    return v.options.map((opt) => ({
      value: opt.key,
      label: opt.value || opt.key,
    }));
  }
  return [];
});

const isFreeTextValue = computed(() => valueOptions.value.length === 0);

function update(field: string, value: string | null) {
  const updated = { ...rule, [field]: value };
  if (field === "sheet") {
    updated.variable = null;
    updated.operator = "equals";
    updated.value = null;
  } else if (field === "variable") {
    const v = findVariable(variables, rule.sheet, value);
    if (v) {
      const ops = operatorsForType(v.block_type);
      if (ops.length > 0) updated.operator = ops[0];
    }
    updated.value = null;
  } else if (field === "operator") {
    const oldOp = rule.operator || "equals";
    if (NO_VALUE_OPERATORS.has(value as ConditionOperator) !== NO_VALUE_OPERATORS.has(oldOp)) {
      updated.value = null;
    }
  }
  emit("update:rule", updated);
}
</script>

<template>
  <div class="condition-rule-row">
    <div class="flex flex-wrap items-baseline gap-1 flex-1">
      <VariableCombobox
        :model-value="rule.sheet || ''"
        :options="sheetOptions"
        placeholder="sheet"
        :disabled="disabled"
        @update:model-value="(v) => update('sheet', v)"
      />
      <span class="sentence-text">&middot;</span>
      <VariableCombobox
        :model-value="rule.variable || ''"
        :groups="variableGroups"
        placeholder="variable"
        :disabled="disabled || !rule.sheet"
        @update:model-value="(v) => update('variable', v)"
      />
      <VariableCombobox
        :model-value="rule.operator || ''"
        :options="operatorOptions"
        placeholder="op"
        :disabled="disabled || !rule.variable"
        @update:model-value="(v) => update('operator', v)"
      />
      <template v-if="needsValue">
        <VariableCombobox
          v-if="!isFreeTextValue"
          :model-value="rule.value || ''"
          :options="valueOptions"
          placeholder="value"
          :disabled="disabled || !rule.operator"
          @update:model-value="(v) => update('value', v)"
        />
        <VariableCombobox
          v-else
          :model-value="rule.value || ''"
          placeholder="value"
          :disabled="disabled || !rule.operator"
          free-text
          @update:model-value="(v) => update('value', v)"
        />
      </template>
    </div>
    <button
      v-if="!disabled"
      type="button"
      class="sp-row-action sp-row-action-danger"
      @click="emit('remove')"
    >
      <X class="size-3" />
    </button>
  </div>
</template>
