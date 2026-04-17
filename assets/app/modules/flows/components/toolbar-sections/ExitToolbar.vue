<script setup lang="ts">
import { ArrowRightToLine, ExternalLink } from "lucide-vue-next";
import { ToolbarColorPicker, ToolbarSeparator } from "@components/toolbar/index.ts";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
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
    class="toolbar-input text-xs"
    :placeholder="$t('flows.exit_toolbar.label_placeholder')"
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
  <ToolbarTooltip v-if="nodeData.referenced_flow_id" :label="$t('flows.exit_toolbar.open_flow')">
    <button
      type="button"
      class="toolbar-btn"
      @click="navigateToExitFlow(nodeData.referenced_flow_id!)"
    >
      <ExternalLink class="size-3.5" />
    </button>
  </ToolbarTooltip>
</template>
