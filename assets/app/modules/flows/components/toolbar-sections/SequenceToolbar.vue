<script setup lang="ts">
import { Layers, Settings } from "lucide-vue-next";

import { ToolbarSeparator } from "@components/toolbar/index.ts";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useLive } from "@composables/useLive";
import type { NodeData } from "../../lib/node-configs";

defineOptions({ inheritAttrs: false });

interface SequenceToolbarData extends NodeData {
  name?: string;
}

const { nodeData, nodeId } = defineProps<{
  nodeData: SequenceToolbarData;
  nodeId: string | number;
}>();

const live = useLive();

function commitName(event: FocusEvent | KeyboardEvent) {
  const target = event.target as HTMLInputElement | null;
  if (!target) return;
  const trimmed = target.value.trim();
  const current = nodeData.name || "";
  if (!trimmed || trimmed === current) {
    // Revert empty / unchanged. Re-set the field to the canonical value so
    // the visible input never shows an uncommitted blank.
    target.value = current;
    return;
  }
  live.pushEvent("update_sequence_name", { id: nodeId, name: trimmed });
}

function openConfig() {
  live.pushEvent("open_sequence_config", { id: nodeId });
}
</script>

<template>
  <component :is="Layers" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <input
    type="text"
    class="toolbar-input text-xs"
    :placeholder="$t('flows.sequences.name_placeholder')"
    :value="nodeData.name || ''"
    data-testid="flow-sequence-name-input"
    @blur="commitName"
    @keydown.enter="(e: KeyboardEvent) => (e.target as HTMLInputElement).blur()"
    @pointerdown.stop
    @keydown.stop
  />
  <ToolbarSeparator />
  <ToolbarTooltip :label="$t('flows.sequences.toolbar_open_config')">
    <button type="button" class="toolbar-btn" @click="openConfig">
      <Settings class="size-3.5" />
    </button>
  </ToolbarTooltip>
</template>
