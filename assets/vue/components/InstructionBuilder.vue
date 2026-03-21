<script setup>
/**
 * Variable assignment editor — "set variable X = value"
 *
 * Builds assignments array: [{ variable_ref, operation, value }]
 * Emits the full array on change for the parent to persist.
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
  assignments: { type: Array, default: () => [] },
  variables: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
})

const emit = defineEmits(["update:assignments"])

const operations = [
  { value: "set", label: "=" },
  { value: "add", label: "+=" },
  { value: "subtract", label: "-=" },
  { value: "multiply", label: "*=" },
  { value: "toggle", label: "toggle" },
]

function addAssignment() {
  const updated = [
    ...props.assignments,
    { variable_ref: "", operation: "set", value: "" },
  ]
  emit("update:assignments", updated)
}

function removeAssignment(index) {
  emit(
    "update:assignments",
    props.assignments.filter((_, i) => i !== index),
  )
}

function updateAssignment(index, field, value) {
  const updated = props.assignments.map((a, i) =>
    i === index ? { ...a, [field]: value } : a,
  )
  emit("update:assignments", updated)
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
      v-for="(assignment, index) in assignments"
      :key="index"
      class="flex items-center gap-1.5"
    >
      <Select
        :model-value="assignment.variable_ref"
        :disabled="disabled"
        @update:model-value="(v) => updateAssignment(index, 'variable_ref', v)"
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
        :model-value="assignment.operation"
        :disabled="disabled"
        @update:model-value="(v) => updateAssignment(index, 'operation', v)"
      >
        <SelectTrigger class="w-16 h-8 text-xs">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem
            v-for="op in operations"
            :key="op.value"
            :value="op.value"
          >
            {{ op.label }}
          </SelectItem>
        </SelectContent>
      </Select>

      <Input
        v-if="assignment.operation !== 'toggle'"
        :model-value="assignment.value"
        :disabled="disabled"
        class="flex-1 h-8 text-xs"
        placeholder="Value"
        @update:model-value="(v) => updateAssignment(index, 'value', v)"
      />

      <Button
        v-if="!disabled"
        variant="ghost"
        size="xs"
        @click="removeAssignment(index)"
      >
        <X class="size-3" />
      </Button>
    </div>

    <Button
      v-if="!disabled"
      variant="outline"
      size="xs"
      class="w-full"
      @click="addAssignment"
    >
      <Plus class="size-3" />
      Add assignment
    </Button>
  </div>
</template>
