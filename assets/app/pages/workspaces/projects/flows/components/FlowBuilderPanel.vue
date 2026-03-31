<script setup>
import { GitBranch, X, Zap } from "lucide-vue-next";
import { computed } from "vue";
import ConditionBuilder from "@components/builders/ConditionBuilder.vue";
import InstructionBuilder from "@components/builders/InstructionBuilder.vue";
import Sidebar from "@components/layout/Sidebar.vue";
import { useLive } from "@composables/useLive.js";

const props = defineProps({
  open: { type: Boolean, default: false },
  nodeType: { type: String, default: null },
  nodeId: { type: [Number, String], default: null },
  condition: { type: Object, default: null },
  assignments: { type: Array, default: () => [] },
  switchMode: { type: Boolean, default: false },
  projectVariables: { default: "[]" },
  canEdit: { type: Boolean, default: false },
});

const live = useLive();

const parsedVariables = computed(() => {
  if (Array.isArray(props.projectVariables)) return props.projectVariables;
  try {
    return JSON.parse(props.projectVariables);
  } catch {
    return [];
  }
});

const title = computed(() => {
  if (props.nodeType === "condition") return "Condition Builder";
  if (props.nodeType === "instruction") return "Instruction Builder";
  return "Builder";
});

const icon = computed(() => {
  if (props.nodeType === "condition") return GitBranch;
  if (props.nodeType === "instruction") return Zap;
  return null;
});

const hasContent = computed(() => {
  if (props.nodeType === "condition") {
    const rules = props.condition?.rules || props.condition?.blocks || [];
    return rules.length > 0;
  }
  if (props.nodeType === "instruction") {
    return props.assignments.length > 0;
  }
  return false;
});

function close() {
  live.pushEvent("close_builder", {});
}

function onConditionUpdate(condition) {
  live.pushEvent("update_condition_builder", { condition });
}

function onAssignmentsUpdate(assignments) {
  live.pushEvent("update_instruction_builder", { assignments });
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between px-3 py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <component :is="icon" v-if="icon" class="size-4" />
          {{ title }}
        </div>
        <button
          type="button"
          class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
          @click="close"
        >
          <X class="size-4" />
        </button>
      </div>
    </template>

    <!-- Condition Builder -->
    <template v-if="nodeType === 'condition'">
      <ConditionBuilder
        :condition="condition"
        :variables="parsedVariables"
        :disabled="!canEdit"
        :switch-mode="switchMode"
        @update:condition="onConditionUpdate"
      />
      <p v-if="!hasContent && !switchMode" class="text-xs text-muted-foreground mt-2">
        Add rules to define when to route to True/False.
      </p>
      <p v-if="!hasContent && switchMode" class="text-xs text-muted-foreground mt-2">
        Add conditions. Each one creates a separate output.
      </p>
    </template>

    <!-- Instruction Builder -->
    <template v-else-if="nodeType === 'instruction'">
      <InstructionBuilder
        :assignments="assignments"
        :variables="parsedVariables"
        :disabled="!canEdit"
        @update:assignments="onAssignmentsUpdate"
      />
      <p v-if="!hasContent && canEdit" class="text-xs text-muted-foreground mt-2">
        Add assignments to set variable values when this node executes.
      </p>
    </template>
  </Sidebar>
</template>
