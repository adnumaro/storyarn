<script setup lang="ts">
/**
 * Tabbed expression editor: Builder | Code.
 *
 * Builder tab: ConditionBuilder or InstructionBuilder (visual).
 * Code tab: CodeMirror 6 with Lezer grammar, autocomplete, linting, formatting.
 */

import { AlignLeft } from "lucide-vue-next";
import { computed, ref, toRef, watch } from "vue";
import { Button } from "@components/ui/button";
import ConditionBuilder from "../builders/ConditionBuilder.vue";
import InstructionBuilder from "../builders/InstructionBuilder.vue";
import { useCodeEditor } from "@shared/composables/useCodeEditor";
import {
  serializeCondition,
  serializeAssignments,
} from "../../shared/domain/operators/expression-serializer";
import type { Variable } from "../../shared/domain/variables";
import type {
  ConditionData,
  ConditionBlock,
  ConditionRule,
  Assignment,
} from "@components/builders/types";
import type { ParsedCondition, ParsedAssignment } from "@plugins/expression-editor/tree-parser";

const {
  mode,
  condition = null,
  assignments = [],
  variables = [],
  disabled = false,
  switchMode = false,
  fillHeight = false,
} = defineProps<{
  mode: "condition" | "instruction";
  condition?: ConditionData | null;
  assignments?: Assignment[];
  variables?: Variable[];
  disabled?: boolean;
  switchMode?: boolean;
  fillHeight?: boolean;
}>();

const emit = defineEmits<{
  "update:condition": [condition: ConditionData];
  "update:assignments": [assignments: Assignment[]];
}>();

const activeTab = ref("builder");
const codeEditorRef = ref<HTMLDivElement | null>(null);
const codeTabActive = computed(() => activeTab.value === "code");

const { setContent, format } = useCodeEditor(codeEditorRef, {
  mode: toRef(() => mode),
  variables: toRef(() => variables),
  disabled: toRef(() => disabled),
  active: codeTabActive,
  placeholder: mode === "condition" ? "mc.health > 50 && mc.alive" : "mc.health = 100",
  onConditionChange(parsed: ParsedCondition) {
    emit("update:condition", parsedConditionToConditionData(parsed));
  },
  onAssignmentsChange(parsed: ParsedAssignment[]) {
    emit("update:assignments", parsedAssignmentsToAssignments(parsed));
  },
});

// When switching to Code tab, serialize current Builder data into the editor
watch(activeTab, (tab) => {
  if (tab === "code") {
    const text =
      mode === "condition"
        ? serializeCondition(condition as Parameters<typeof serializeCondition>[0])
        : serializeAssignments(assignments as Parameters<typeof serializeAssignments>[0]);
    setContent(text);
  }
});

// -- Type conversions (parsed tree types → builder types) --

function parsedConditionToConditionData(parsed: ParsedCondition): ConditionData {
  return {
    logic: parsed.logic,
    blocks: parsed.rules.map(
      (rule): ConditionBlock => ({
        id: rule.id,
        type: "block",
        logic: "all",
        rules: [
          {
            id: `${rule.id}_r`,
            sheet: rule.sheet,
            variable: rule.variable,
            operator: rule.operator as ConditionRule["operator"],
            value: rule.value,
          },
        ],
      }),
    ),
  };
}

function parsedAssignmentsToAssignments(parsed: ParsedAssignment[]): Assignment[] {
  return parsed.map((a) => ({
    operator: a.operator as Assignment["operator"],
    sheet: a.sheet,
    variable: a.variable,
    value_type: a.value_type,
    value: a.value,
    value_sheet: a.value_sheet,
  }));
}
</script>

<template>
  <div :class="['expression-editor', fillHeight && 'flex flex-col min-h-0']">
    <!-- Tabs -->
    <div :class="['flex items-center gap-1 mb-3', fillHeight && 'shrink-0']">
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
        {{ $t("common.expression_editor.builder") }}
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
        {{ $t("common.expression_editor.code") }}
      </button>

      <!-- Format button (only on Code tab) -->
      <Button
        v-if="activeTab === 'code' && !disabled"
        variant="ghost"
        size="xs"
        class="ml-auto"
        :title="$t('common.expression_editor.format_code')"
        @click="format()"
      >
        <AlignLeft :size="14" />
        {{ $t("common.expression_editor.format") }}
      </Button>
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

    <!-- Code tab -->
    <div
      v-show="activeTab === 'code'"
      ref="codeEditorRef"
      :class="[
        'rounded-lg border border-border overflow-hidden',
        fillHeight ? 'flex-1 min-h-0 [&_.cm-editor]:h-full' : 'min-h-30',
      ]"
    />
  </div>
</template>
