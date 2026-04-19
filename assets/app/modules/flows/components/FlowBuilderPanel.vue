<script setup lang="ts">
import { GitBranch, X, Zap } from "lucide-vue-next";
import type { Component } from "vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import type { Assignment, ConditionData } from "@components/builders/types";
import ExpressionEditor from "@components/ExpressionEditor.vue";
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

const { t } = useI18n();
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
  if (nodeType === "condition") return t("flows.builder.condition_title");
  if (nodeType === "instruction") return t("flows.builder.instruction_title");
  return t("flows.builder.fallback_title");
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

    <div
      v-if="nodeType === 'condition' || nodeType === 'instruction'"
      class="flex flex-col h-full"
    >
      <ExpressionEditor
        :mode="nodeType"
        :condition="condition"
        :assignments="assignments"
        :variables="parsedVariables"
        :disabled="!canEdit"
        :switch-mode="switchMode"
        fill-height
        class="flex-1 min-h-0"
        @update:condition="onConditionUpdate"
        @update:assignments="onAssignmentsUpdate"
      />
      <p
        v-if="nodeType === 'condition' && !hasContent && !switchMode"
        class="shrink-0 text-xs text-muted-foreground mt-2"
      >
        {{ $t("flows.builder.condition_help") }}
      </p>
      <p
        v-if="nodeType === 'condition' && !hasContent && switchMode"
        class="shrink-0 text-xs text-muted-foreground mt-2"
      >
        {{ $t("flows.builder.condition_switch_help") }}
      </p>
      <p
        v-if="nodeType === 'instruction' && !hasContent && canEdit"
        class="shrink-0 text-xs text-muted-foreground mt-2"
      >
        {{ $t("flows.builder.instruction_help") }}
      </p>
    </div>
  </Sidebar>
</template>
