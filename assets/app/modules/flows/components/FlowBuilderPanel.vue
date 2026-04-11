<script setup lang="ts">
import { GitBranch, X, Zap } from "lucide-vue-next";
import type { Component } from "vue";
import { computed } from "vue";
import ConditionBuilder from "@components/builders/ConditionBuilder.vue";
import InstructionBuilder from "@components/builders/InstructionBuilder.vue";
import type { Assignment, ConditionData } from "@components/builders/types";
import Sidebar from "@components/layout/Sidebar.vue";
import type { Variable } from "@modules/shared/variables";
import { useLive } from "@composables/useLive";

const {
  open = false,
  nodeType = null,
  condition = null,
  assignments = [],
  switchMode = false,
  projectVariables = "[]",
  canEdit = false,
} = defineProps<{
  open?: boolean;
  nodeType?: string | null;
  nodeId?: number | string | null;
  condition?: ConditionData | null;
  assignments?: Assignment[];
  switchMode?: boolean;
  projectVariables?: Variable[] | string;
  canEdit?: boolean;
}>();

const live = useLive();

const parsedVariables = computed<Variable[]>(() => {
  if (Array.isArray(projectVariables)) return projectVariables;
  try {
    return JSON.parse(projectVariables);
  } catch {
    return [];
  }
});

const title = computed(() => {
  if (nodeType === "condition") return "Condition Builder";
  if (nodeType === "instruction") return "Instruction Builder";
  return "Builder";
});

const icon = computed<Component | null>(() => {
  if (nodeType === "condition") return GitBranch;
  if (nodeType === "instruction") return Zap;
  return null;
});

const hasContent = computed(() => {
  if (nodeType === "condition") {
    return (condition?.blocks?.length ?? 0) > 0;
  }
  if (nodeType === "instruction") {
    return assignments.length > 0;
  }
  return false;
});

function close() {
  live.pushEvent("close_builder", {});
}

function onConditionUpdate(condition: ConditionData): void {
  live.pushEvent("update_condition_builder", { condition });
}

function onAssignmentsUpdate(updatedAssignments: Assignment[]): void {
  live.pushEvent("update_instruction_builder", { assignments: updatedAssignments });
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
