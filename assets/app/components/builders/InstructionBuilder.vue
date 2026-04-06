<script setup lang="ts">
/**
 * Variable assignment editor — instruction builder.
 * Wraps in .instruction-builder for sentence-flow CSS.
 *
 * Maintains internal reactive state (like ConditionBuilder) so changes
 * are reflected immediately without waiting for LiveView prop updates.
 */

import { Plus } from "lucide-vue-next";
import { ref, watch } from "vue";
import type { Variable } from "@modules/shared/variables";
import type { Assignment } from "./types";
import AssignmentRow from "@components/builders/instruction/AssignmentRow.vue";

const { assignments = [], variables = [], disabled = false } = defineProps<{
  assignments?: Assignment[];
  variables?: Variable[];
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:assignments": [assignments: Assignment[]];
}>();

const internalAssignments = ref([...assignments]);

watch(
  () => assignments,
  (v) => {
    internalAssignments.value = [...v];
  },
  { deep: true },
);

function emitUpdate() {
  emit("update:assignments", [...internalAssignments.value]);
}

function addAssignment() {
  const newAssignment: Assignment = {
    operator: "set",
    sheet: null,
    variable: null,
    value_type: "literal",
    value: null,
    value_sheet: null,
  };
  internalAssignments.value = [...internalAssignments.value, newAssignment];
  emitUpdate();
}

function updateAssignment(index: number, updated: Assignment) {
  const arr = [...internalAssignments.value];
  arr[index] = updated;
  internalAssignments.value = arr;
  emitUpdate();
}

function removeAssignment(index: number) {
  internalAssignments.value = internalAssignments.value.filter((_, i) => i !== index);
  emitUpdate();
}
</script>

<template>
  <div class="instruction-builder">
    <AssignmentRow
      v-for="(assignment, index) in internalAssignments"
      :key="index"
      :assignment="assignment"
      :variables="variables"
      :disabled="disabled"
      @update:assignment="(a) => updateAssignment(index, a)"
      @remove="removeAssignment(index)"
    />

    <button
      v-if="!disabled"
      type="button"
      class="inline-flex items-center justify-center gap-1 w-full mt-1 px-2 py-1 text-xs text-muted-foreground border border-dashed border-border rounded hover:bg-accent/50 transition-colors"
      @click="addAssignment"
    >
      <Plus class="size-3" />
      Add assignment
    </button>

    <p
      v-if="internalAssignments.length === 0 && disabled"
      class="text-xs text-muted-foreground italic py-2"
    >
      No assignments set
    </p>
  </div>
</template>
