<script setup lang="ts">
import { Crosshair, LogIn } from "lucide-vue-next";
import { ToolbarSeparator } from "@components/toolbar/index.ts";
import { useLive } from "@composables/useLive";
import type { NodeData } from "../../lib/node-configs";
import type { ReferencingJump } from "../../types";

interface HubToolbarData extends NodeData {
  label?: string;
  hub_id?: string;
}

const {
  nodeData,
  nodeId,
  referencingJumps = [],
} = defineProps<{
  nodeData: HubToolbarData;
  nodeId: string | number;
  referencingJumps?: ReferencingJump[];
}>();

const live = useLive();

function updateField(field: string, value: unknown) {
  live.pushEvent("update_node_data", { node: { [field]: value } });
}

function navigateToJumps() {
  live.pushEvent("navigate_to_jumps", { id: nodeId });
}
</script>

<template>
  <component :is="LogIn" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <input
    type="text"
    class="toolbar-input text-xs"
    :placeholder="$t('flows.hub_toolbar.label_placeholder')"
    :value="nodeData.label || ''"
    @blur="(e: FocusEvent) => updateField('label', (e.target as HTMLInputElement).value)"
    @keydown.enter="(e: KeyboardEvent) => (e.target as HTMLInputElement).blur()"
    @pointerdown.stop
    @keydown.stop
  />
  <input
    type="text"
    class="toolbar-input text-xs font-mono"
    :placeholder="$t('flows.hub_toolbar.hub_id_placeholder')"
    :value="nodeData.hub_id || ''"
    @blur="(e: FocusEvent) => updateField('hub_id', (e.target as HTMLInputElement).value)"
    @keydown.enter="(e: KeyboardEvent) => (e.target as HTMLInputElement).blur()"
    @pointerdown.stop
    @keydown.stop
  />
  <button
    v-if="referencingJumps.length > 0"
    type="button"
    class="toolbar-btn"
    :title="$t('flows.hub_toolbar.locate_jumps')"
    @click="navigateToJumps"
  >
    <Crosshair class="size-3.5" />
  </button>
</template>
