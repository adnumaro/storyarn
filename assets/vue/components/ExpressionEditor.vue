<script setup>
/**
 * Tabbed expression editor: Builder | Code.
 *
 * Builder tab: ConditionBuilder or InstructionBuilder (visual).
 * Code tab: CodeMirror 6 with syntax highlighting, autocomplete, and linting.
 * Reuses the existing createExpressionEditor from the JS codebase.
 */

import { ref, computed, watch, onMounted, onBeforeUnmount, nextTick } from "vue"
import ConditionBuilder from "./ConditionBuilder.vue"
import InstructionBuilder from "./InstructionBuilder.vue"
import { serializeCondition, serializeAssignments } from "@/vue/lib/expression-serializer"
import { createExpressionEditor } from "@/js/expression_editor/setup.js"
import { formatExpression } from "@/js/expression_editor/formatter.js"
import { parseCondition, parseAssignments } from "@/js/expression_editor/parser.js"

const props = defineProps({
  mode: { type: String, required: true, validator: (v) => ["condition", "instruction"].includes(v) },
  condition: { type: [Object, null], default: null },
  assignments: { type: Array, default: () => [] },
  variables: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  switchMode: { type: Boolean, default: false },
})

const emit = defineEmits(["update:condition", "update:assignments"])

const activeTab = ref("builder")
const codeContainer = ref(null)
let editorInstance = null
let isFormatting = false
let formatTimer = null

const cmMode = computed(() => props.mode === "condition" ? "expression" : "assignments")

/** Serialize current data to DSL text for the code editor */
const serializedText = computed(() => {
  if (props.mode === "condition") return serializeCondition(props.condition) || ""
  return serializeAssignments(props.assignments) || ""
})

function mountEditor() {
  if (!codeContainer.value || editorInstance) return

  editorInstance = createExpressionEditor({
    container: codeContainer.value,
    content: serializedText.value,
    mode: cmMode.value,
    editable: !props.disabled,
    placeholderText: props.mode === "condition" ? "mc.jaime.health > 50" : "mc.jaime.health = 50",
    variables: props.variables,
    onChange: (text) => {
      if (isFormatting) return
      pushParsedData(text)
    },
  })

  // Auto-format on mount
  if (serializedText.value) formatCode()
}

function destroyEditor() {
  editorInstance?.destroy()
  editorInstance = null
  clearTimeout(formatTimer)
}

function formatCode() {
  if (!editorInstance) return
  const text = editorInstance.getContent()
  const formatted = formatExpression(text, cmMode.value)
  if (formatted === text) return

  isFormatting = true
  clearTimeout(formatTimer)
  editorInstance.setContent(formatted)
  formatTimer = setTimeout(() => { isFormatting = false }, 350)
}

function pushParsedData(text) {
  if (props.mode === "condition") {
    const result = parseCondition(text, props.variables)
    if (result.errors.length > 0) return
    emit("update:condition", result.condition || { logic: "all", rules: [] })
  } else {
    const result = parseAssignments(text, props.variables)
    if (result.errors.length > 0) return
    const assignments = (result.assignments || []).map(
      ({ ref_from, ref_to, value_ref_from, value_ref_to, ...a }) => a,
    )
    emit("update:assignments", assignments)
  }
}

// When switching to code tab, mount editor and sync content
watch(activeTab, async (tab) => {
  if (tab === "code") {
    await nextTick()
    if (!editorInstance) {
      mountEditor()
    } else {
      // Sync content from builder
      const text = serializedText.value
      const formatted = formatExpression(text, cmMode.value)
      isFormatting = true
      clearTimeout(formatTimer)
      editorInstance.setContent(formatted || text)
      formatTimer = setTimeout(() => { isFormatting = false }, 350)
    }
  }
})

onBeforeUnmount(() => {
  destroyEditor()
})
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
      <button
        v-if="activeTab === 'code' && !disabled"
        type="button"
        class="ml-auto px-2 py-1 text-xs text-muted-foreground rounded hover:bg-accent transition-colors"
        @click="formatCode"
      >
        Format
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

    <!-- Code tab -->
    <div v-show="activeTab === 'code'"
      ref="codeContainer"
      class="min-h-[120px] rounded-lg overflow-hidden"
    />
  </div>
</template>
