<script setup>
/**
 * Variable assignment editor — instruction builder.
 * Wraps in .instruction-builder for sentence-flow CSS.
 *
 * Maintains internal reactive state (like ConditionBuilder) so changes
 * are reflected immediately without waiting for LiveView prop updates.
 */

import { ref, watch } from "vue";
import { Plus } from "lucide-vue-next";
import AssignmentRow from "./instruction/AssignmentRow.vue";

const props = defineProps({
	assignments: { type: Array, default: () => [] },
	variables: { type: Array, default: () => [] },
	disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:assignments"]);

const internalAssignments = ref([...props.assignments]);

watch(
	() => props.assignments,
	(v) => {
		internalAssignments.value = [...v];
	},
	{ deep: true },
);

function emitUpdate() {
	emit("update:assignments", [...internalAssignments.value]);
}

function addAssignment() {
	internalAssignments.value = [
		...internalAssignments.value,
		{
			operator: "set",
			sheet: null,
			variable: null,
			value_type: "literal",
			value: null,
			value_sheet: null,
		},
	];
	emitUpdate();
}

function updateAssignment(index, updated) {
	const arr = [...internalAssignments.value];
	arr[index] = updated;
	internalAssignments.value = arr;
	emitUpdate();
}

function removeAssignment(index) {
	internalAssignments.value = internalAssignments.value.filter(
		(_, i) => i !== index,
	);
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

    <p v-if="internalAssignments.length === 0 && disabled" class="text-xs text-muted-foreground italic py-2">
      No assignments set
    </p>
  </div>
</template>
