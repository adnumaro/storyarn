<script setup lang="ts">
/**
 * Tabbed expression editor: Builder | Code.
 *
 * Builder tab: ConditionBuilder or InstructionBuilder (visual).
 * Code tab: TODO — needs CodeMirror with Lezer grammar rebuild for V2.
 */

import { ref } from "vue";
import ConditionBuilder from "./builders/ConditionBuilder.vue";
import InstructionBuilder from "./builders/InstructionBuilder.vue";
import type { Variable } from "@modules/shared/variables";
import type { ConditionData, Assignment } from "./builders/types";

const { mode, condition = null, assignments = [], variables = [], disabled = false, switchMode = false } = defineProps<{
  mode: "condition" | "instruction";
  condition?: ConditionData | null;
  assignments?: Assignment[];
  variables?: Variable[];
  disabled?: boolean;
  switchMode?: boolean;
}>();

const emit = defineEmits<{
  "update:condition": [condition: ConditionData];
  "update:assignments": [assignments: Assignment[]];
}>();

const activeTab = ref("builder");
</script>

<template>
  <div class="expression-editor">
    <!-- Tabs -->
    <div class="flex items-center gap-1 mb-3">
      <button
        type="button"
        :class="[
          'px-3 py-1 text-sm rounded-full font-medium transition-colors',
          activeTab === 'builder'
            ? 'bg-accent text-accent-foreground'
            : 'text-muted-foreground hover:text-foreground',
        ]"
        @click="activeTab = 'builder'"
      >
        Builder
      </button>
      <button
        type="button"
        :class="[
          'px-3 py-1 text-sm rounded-full font-medium transition-colors',
          activeTab === 'code'
            ? 'bg-accent text-accent-foreground'
            : 'text-muted-foreground hover:text-foreground',
        ]"
        @click="activeTab = 'code'"
      >
        Code
      </button>
    </div>

    <!-- Builder tab -->
    <div v-show="activeTab === 'builder'">
      <ConditionBuilder
        v-if="mode === 'condition'"
        :condition="condition"
        :variables="variables"
        :disabled="disabled"
        :switch-mode="switchMode"
        @update:condition="(c) => emit('update:condition', c)"
      />
      <InstructionBuilder
        v-if="mode === 'instruction'"
        :assignments="assignments"
        :variables="variables"
        :disabled="disabled"
        @update:assignments="(a) => emit('update:assignments', a)"
      />
    </div>

    <!-- Code tab (pending CodeMirror rebuild) -->
    <div
      v-show="activeTab === 'code'"
      class="min-h-[120px] rounded-lg border border-border p-4 flex items-center justify-center"
    >
      <span class="text-sm text-muted-foreground">Code editor pending migration</span>
    </div>
  </div>
</template>
