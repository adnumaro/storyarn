<script setup>
import { ArrowRightToLine, ExternalLink } from "lucide-vue-next";
import { ToolbarColorPicker, ToolbarSeparator } from "@components/shared/toolbar/index.js";
import { useLive } from "@composables/useLive.js";
import { ToolbarExitModePicker } from "../../toolbar/index.js";

const { nodeData } = defineProps({
  nodeData: { type: Object, required: true },
});

const live = useLive();

function updateField(field, value) {
  live.pushEvent("update_node_data", { node: { [field]: value } });
}

function updateExitMode(mode) {
  live.pushEvent("update_exit_mode", { mode });
}

function updateOutcomeColor(color) {
  live.pushEvent("update_outcome_color", { value: color });
}

function navigateToExitFlow(flowId) {
  live.pushEvent("navigate_to_exit_flow", { "flow-id": String(flowId) });
}
</script>

<template>
  <component :is="ArrowRightToLine" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <input
    type="text"
    class="v2-toolbar-input text-xs"
    placeholder="Label…"
    :value="nodeData.label || ''"
    @blur="(e) => updateField('label', e.target.value)"
    @keydown.enter="(e) => e.target.blur()"
    @pointerdown.stop
    @keydown.stop
  />
  <ToolbarExitModePicker :mode="nodeData.exit_mode || 'terminal'" @update:mode="updateExitMode" />
  <ToolbarColorPicker
    :color="nodeData.outcome_color || '#22c55e'"
    @update:color="updateOutcomeColor"
  />
  <button
    v-if="nodeData.referenced_flow_id"
    type="button"
    class="v2-toolbar-btn"
    title="Open referenced flow"
    @click="navigateToExitFlow(nodeData.referenced_flow_id)"
  >
    <ExternalLink class="size-3.5" />
  </button>
</template>
