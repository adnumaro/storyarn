<script setup lang="ts">
import { ArrowRightToLine, ExternalLink } from "lucide-vue-next";
import { ToolbarColorPicker, ToolbarSeparator } from "@components/toolbar/index.ts";
import { useLive } from "@composables/useLive";
import { ToolbarExitModePicker } from "../../toolbar";
import type { NodeData } from "../../lib/node-configs";

interface ExitToolbarData extends NodeData {
  label?: string;
  exit_mode?: string;
  outcome_color?: string;
  referenced_flow_id?: number | string | null;
}

const { nodeData } = defineProps<{
  nodeData: ExitToolbarData;
}>();

const live = useLive();

function updateField(field: string, value: unknown) {
  live.pushEvent("update_node_data", { node: { [field]: value } });
}

function updateExitMode(mode: string) {
  live.pushEvent("update_exit_mode", { mode });
}

function updateOutcomeColor(color: string) {
  live.pushEvent("update_outcome_color", { value: color });
}

function navigateToExitFlow(flowId: number | string) {
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
    @blur="(e: FocusEvent) => updateField('label', (e.target as HTMLInputElement).value)"
    @keydown.enter="(e: KeyboardEvent) => (e.target as HTMLInputElement).blur()"
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
    @click="navigateToExitFlow(nodeData.referenced_flow_id!)"
  >
    <ExternalLink class="size-3.5" />
  </button>
</template>
