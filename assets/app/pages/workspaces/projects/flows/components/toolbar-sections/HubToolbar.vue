<script setup>
import { Crosshair, LogIn } from "lucide-vue-next";
import { ToolbarSeparator } from "@components/shared/toolbar/index.js";
import { useLive } from "@composables/useLive.js";

const props = defineProps({
  nodeData: { type: Object, required: true },
  nodeId: { type: [String, Number], required: true },
  referencingJumps: { type: Array, default: () => [] },
});

const live = useLive();

function updateField(field, value) {
  live.pushEvent("update_node_data", { node: { [field]: value } });
}

function navigateToJumps() {
  live.pushEvent("navigate_to_jumps", { id: props.nodeId });
}
</script>

<template>
  <component :is="LogIn" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <input
    type="text"
    class="v2-toolbar-input text-xs"
    placeholder="Label"
    :value="nodeData.label || ''"
    @blur="(e) => updateField('label', e.target.value)"
    @keydown.enter="(e) => e.target.blur()"
    @pointerdown.stop
    @keydown.stop
  />
  <input
    type="text"
    class="v2-toolbar-input text-xs font-mono"
    placeholder="hub_id"
    :value="nodeData.hub_id || ''"
    @blur="(e) => updateField('hub_id', e.target.value)"
    @keydown.enter="(e) => e.target.blur()"
    @pointerdown.stop
    @keydown.stop
  />
  <button
    v-if="referencingJumps.length > 0"
    type="button"
    class="v2-toolbar-btn"
    title="Locate jumps"
    @click="navigateToJumps"
  >
    <Crosshair class="size-3.5" />
  </button>
</template>
