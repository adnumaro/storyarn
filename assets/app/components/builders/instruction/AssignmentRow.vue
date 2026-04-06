<script setup lang="ts">
/**
 * Single assignment row — sentence-template layout.
 * Uses .assignment-row, .sentence-text, .sentence-slot, .operator-selector CSS.
 */

import { ArrowLeftRight, X } from "lucide-vue-next";
import { computed, ref } from "vue";
import {
  ALL_OPERATORS,
  expandTemplateForVariableRef,
  getTemplate,
  NO_VALUE_OPERATORS,
  OPERATOR_DROPDOWN_LABELS,
  OPERATOR_VERBS,
  operatorsForType,
  typesForOperator,
} from "@modules/shared/operators/instruction-operators";
import type { InstructionOperator } from "@modules/shared/operators/instruction-operators";
import { findVariable, groupVariablesBySheet } from "@modules/shared/variables";
import type { Variable } from "@modules/shared/variables";
import type { Assignment } from "../types";
import { Popover, PopoverContent, PopoverTrigger } from "../../ui/popover/index.ts";
import VariableCombobox from "../../VariableCombobox.vue";

const {
  assignment,
  variables = [],
  disabled = false,
} = defineProps<{
  assignment: Assignment;
  variables?: Variable[];
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:assignment": [assignment: Assignment];
  remove: [];
}>();
const operatorDropdownOpen = ref(false);

const sheetsWithVariables = computed(() => groupVariablesBySheet(variables));

const variableType = computed(() => {
  const v = findVariable(variables, assignment.sheet, assignment.variable);
  return v ? v.block_type : null;
});

const availableOperators = computed(() =>
  variableType.value ? operatorsForType(variableType.value) : ALL_OPERATORS,
);

const template = computed(() => {
  const op = assignment.operator || "set";
  let t = getTemplate(op);
  const hasValueSlot = t.some((item) => item.type === "slot" && item.key === "value");
  if (hasValueSlot && assignment.value_type === "variable_ref" && !NO_VALUE_OPERATORS.has(op)) {
    t = expandTemplateForVariableRef(t);
  }
  return t;
});

const sheetOptions = computed(() => {
  const ct = typesForOperator(assignment.operator || "set");
  const filtered =
    ct === null
      ? sheetsWithVariables.value
      : sheetsWithVariables.value.filter((s) =>
          s.vars.some((v) => (ct as string[]).includes(v.block_type)),
        );
  return filtered.map((s) => ({ value: s.shortcut, label: s.name }));
});

const variableGroups = computed(() => {
  if (!assignment.sheet) return [];
  const sheet = sheetsWithVariables.value.find((s) => s.shortcut === assignment.sheet);
  if (!sheet) return [];
  const ct = typesForOperator(assignment.operator || "set");
  const vars =
    ct === null ? sheet.vars : sheet.vars.filter((v) => (ct as string[]).includes(v.block_type));
  return [
    {
      heading: sheet.name,
      items: vars.map((v) => ({
        value: v.variable_name,
        label: v.variable_name,
      })),
    },
  ];
});

const valueOptions = computed(() => {
  if (assignment.value_type === "variable_ref") {
    const vs = assignment.value_sheet;
    if (!vs) return [];
    const sheet = sheetsWithVariables.value.find((s) => s.shortcut === vs);
    if (!sheet) return [];
    return sheet.vars.map((v) => ({
      value: v.variable_name,
      label: v.variable_name,
    }));
  }
  const v = findVariable(variables, assignment.sheet, assignment.variable);
  if (v && (v.block_type === "select" || v.block_type === "multi_select") && v.options) {
    return v.options.map((opt) => ({
      value: opt.key,
      label: opt.value || opt.key,
    }));
  }
  return [];
});

const valueSheetOptions = computed(() =>
  sheetsWithVariables.value.map((s) => ({ value: s.shortcut, label: s.name })),
);

const isFreeTextValue = computed(
  () => assignment.value_type !== "variable_ref" && valueOptions.value.length === 0,
);

const isNumericValue = computed(
  () =>
    assignment.value_type !== "variable_ref" &&
    (assignment.operator === "add" || assignment.operator === "subtract"),
);

function clearValueUnlessArithmetic(updated: Assignment): void {
  if (updated.operator !== "add" && updated.operator !== "subtract") {
    updated.value = null;
  }
}

function applySheetChange(updated: Assignment): void {
  updated.variable = null;
  clearValueUnlessArithmetic(updated);
  updated.value_sheet = null;
}

function applyVariableChange(updated: Assignment, value: string | null): void {
  const sv = findVariable(variables, assignment.sheet, value);
  if (sv) {
    const ops = operatorsForType(sv.block_type);
    if (!ops.includes(updated.operator) && ops.length > 0) updated.operator = ops[0];
  }
  clearValueUnlessArithmetic(updated);
  updated.value_sheet = null;
}

function update(field: string, value: string | null) {
  const updated = { ...assignment, [field]: value };
  if (field === "sheet") {
    applySheetChange(updated);
  } else if (field === "variable") {
    applyVariableChange(updated, value);
  } else if (field === "value_sheet") {
    updated.value = null;
  }
  emit("update:assignment", updated);
}

function changeOperator(op: InstructionOperator) {
  const updated = { ...assignment, operator: op };
  if (NO_VALUE_OPERATORS.has(op) !== NO_VALUE_OPERATORS.has(assignment.operator)) {
    updated.value = null;
    updated.value_sheet = null;
    updated.value_type = "literal";
  }
  const ct = typesForOperator(op);
  if (ct !== null && updated.variable) {
    const cv = findVariable(variables, updated.sheet, updated.variable);
    if (cv && !(ct as string[]).includes(cv.block_type)) {
      updated.variable = null;
      updated.value = null;
      updated.value_sheet = null;
      updated.value_type = "literal";
    }
  }
  operatorDropdownOpen.value = false;
  emit("update:assignment", updated);
}

function toggleValueType() {
  emit("update:assignment", {
    ...assignment,
    value_type: assignment.value_type === "variable_ref" ? "literal" : "variable_ref",
    value: null,
    value_sheet: null,
  });
}
</script>

<template>
  <div class="assignment-row">
    <div class="flex flex-wrap items-baseline gap-1 flex-1">
      <template v-for="(item, idx) in template" :key="idx">
        <!-- Verb: operator selector -->
        <template v-if="item.type === 'verb'">
          <Popover v-if="!disabled" v-model:open="operatorDropdownOpen">
            <PopoverTrigger as-child>
              <button type="button" class="operator-selector" title="Change operator">
                {{ OPERATOR_VERBS[assignment.operator] || item.value }}
              </button>
            </PopoverTrigger>
            <PopoverContent class="w-40 p-0" align="start" :side-offset="4">
              <div
                v-for="op in availableOperators"
                :key="op"
                :class="['operator-option', { active: op === assignment.operator }]"
                @mousedown.prevent.stop="changeOperator(op)"
              >
                {{ OPERATOR_DROPDOWN_LABELS[op] || op }}
              </div>
            </PopoverContent>
          </Popover>
          <span v-else class="sentence-text font-medium">{{
            OPERATOR_VERBS[assignment.operator] || item.value
          }}</span>
        </template>

        <span v-else-if="item.type === 'text'" class="sentence-text">{{ item.value }}</span>

        <VariableCombobox
          v-else-if="item.type === 'slot' && item.key === 'sheet'"
          :model-value="assignment.sheet || ''"
          :options="sheetOptions"
          :placeholder="item.placeholder"
          :disabled="disabled"
          @update:model-value="(v) => update('sheet', v)"
        />

        <VariableCombobox
          v-else-if="item.type === 'slot' && item.key === 'variable'"
          :model-value="assignment.variable || ''"
          :groups="variableGroups"
          :placeholder="item.placeholder"
          :disabled="disabled || !assignment.sheet"
          @update:model-value="(v) => update('variable', v)"
        />

        <VariableCombobox
          v-else-if="item.type === 'slot' && item.key === 'value_sheet'"
          :model-value="assignment.value_sheet || ''"
          :options="valueSheetOptions"
          :placeholder="item.placeholder"
          :disabled="disabled || !assignment.variable"
          @update:model-value="(v) => update('value_sheet', v)"
        />

        <template v-else-if="item.type === 'slot' && item.key === 'value'">
          <VariableCombobox
            v-if="assignment.value_type === 'variable_ref'"
            :model-value="assignment.value || ''"
            :options="valueOptions"
            :placeholder="item.placeholder"
            :disabled="disabled || !assignment.value_sheet"
            @update:model-value="(v) => update('value', v)"
          />
          <VariableCombobox
            v-else-if="!isFreeTextValue"
            :model-value="assignment.value || ''"
            :options="valueOptions"
            :placeholder="item.placeholder"
            :disabled="disabled || !assignment.variable"
            @update:model-value="(v) => update('value', v)"
          />
          <VariableCombobox
            v-else
            :model-value="assignment.value || ''"
            :placeholder="item.placeholder"
            :disabled="
              disabled ||
              (!assignment.variable &&
                assignment.operator !== 'add' &&
                assignment.operator !== 'subtract')
            "
            free-text
            :input-type="isNumericValue ? 'number' : 'text'"
            @update:model-value="(v) => update('value', v)"
          />
        </template>
      </template>

      <!-- Value type toggle -->
      <button
        v-if="!disabled && assignment.variable && !NO_VALUE_OPERATORS.has(assignment.operator)"
        type="button"
        class="sp-row-action"
        style="opacity: 0.5"
        title="Switch literal / variable reference"
        @click="toggleValueType"
      >
        <ArrowLeftRight class="size-3" />
      </button>
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
