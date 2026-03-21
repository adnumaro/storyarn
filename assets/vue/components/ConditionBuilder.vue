<script setup>
/**
 * Variable condition editor — "if variable X operator Y then..."
 *
 * Builds a condition object: { variable_ref, operator, value, logic }
 * Emits the full condition on change for the parent to persist.
 */

import { computed } from "vue"
import { Button } from "./ui/button"
import { Input } from "./ui/input"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select"
import { X, Plus } from "lucide-vue-next"

const props = defineProps({
  condition: { type: [Object, Array, null], default: null },
  variables: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
})

const emit = defineEmits(["update:condition"])

const operators = [
  { value: "==", label: "=" },
  { value: "!=", label: "≠" },
  { value: ">", label: ">" },
  { value: ">=", label: "≥" },
  { value: "<", label: "<" },
  { value: "<=", label: "≤" },
]

const rules = computed(() => {
  if (!props.condition) return []
  if (Array.isArray(props.condition)) return props.condition
  return [props.condition]
})

function addRule() {
  const updated = [...rules.value, { variable_ref: "", operator: "==", value: "" }]
  emit("update:condition", updated)
}

function removeRule(index) {
  const updated = rules.value.filter((_, i) => i !== index)
  emit("update:condition", updated.length ? updated : null)
}

function updateRule(index, field, value) {
  const updated = rules.value.map((r, i) =>
    i === index ? { ...r, [field]: value } : r,
  )
  emit("update:condition", updated)
}

const variableOptions = computed(() =>
  props.variables.map((v) => ({
    value: v.ref || `${v.sheet_shortcut}.${v.variable_name}`,
    label: v.name || v.variable_name || v.ref,
  })),
)
</script>

<template>
  <div class="space-y-2">
    <div
      v-for="(rule, index) in rules"
      :key="index"
      class="flex items-center gap-1.5"
    >
      <Select
        :model-value="rule.variable_ref"
        :disabled="disabled"
        @update:model-value="(v) => updateRule(index, 'variable_ref', v)"
      >
        <SelectTrigger class="flex-1 h-8 text-xs">
          <SelectValue placeholder="Variable..." />
        </SelectTrigger>
        <SelectContent>
          <SelectItem
            v-for="v in variableOptions"
            :key="v.value"
            :value="v.value"
          >
            {{ v.label }}
          </SelectItem>
        </SelectContent>
      </Select>

      <Select
        :model-value="rule.operator"
        :disabled="disabled"
        @update:model-value="(v) => updateRule(index, 'operator', v)"
      >
        <SelectTrigger class="w-14 h-8 text-xs">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem v-for="op in operators" :key="op.value" :value="op.value">
            {{ op.label }}
          </SelectItem>
        </SelectContent>
      </Select>

      <Input
        :model-value="rule.value"
        :disabled="disabled"
        class="flex-1 h-8 text-xs"
        placeholder="Value"
        @update:model-value="(v) => updateRule(index, 'value', v)"
      />

      <Button
        v-if="!disabled"
        variant="ghost"
        size="xs"
        @click="removeRule(index)"
      >
        <X class="size-3" />
      </Button>
    </div>

    <Button
      v-if="!disabled"
      variant="outline"
      size="xs"
      class="w-full"
      @click="addRule"
    >
      <Plus class="size-3" />
      Add condition
    </Button>
  </div>
</template>
