<script setup lang="ts">
import { Crosshair, LogOut } from "lucide-vue-next";
import { computed } from "vue";
import { ToolbarSeparator } from "@components/toolbar/index.ts";
import { useLive } from "@composables/useLive";
import { ToolbarSearchableSelect } from "../../toolbar";
import type { HubMapEntry } from "../../types";
import type { NodeData } from "../../lib/node-configs";

interface JumpToolbarData extends NodeData {
  target_hub_id?: string;
}

const {
  nodeData,
  nodeId,
  hubs = [],
} = defineProps<{
  nodeData: JumpToolbarData;
  nodeId: string | number;
  hubs?: HubMapEntry[];
}>();

const live = useLive();

const hubOptions = computed<[string, string][]>(() => hubs.map((h) => [h.hub_id, h.hub_id]));

const selectedHubLabel = computed(() => {
  const target = nodeData.target_hub_id;
  if (!target) return null;
  const hub = hubs.find((h) => h.hub_id === target);
  return hub?.hub_id || null;
});

function selectHub(hubId: string) {
  live.pushEvent("update_node_data", { node: { target_hub_id: hubId || "" } });
}

function navigateToHub() {
  live.pushEvent("navigate_to_hub", { id: nodeId });
}
</script>

<template>
  <component :is="LogOut" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <ToolbarSearchableSelect
    :options="hubOptions"
    :selected-value="nodeData.target_hub_id"
    :selected-label="selectedHubLabel"
    placeholder="Target hub…"
    @select="(v: string | number) => selectHub(String(v))"
  />
  <button
    v-if="nodeData.target_hub_id"
    type="button"
    class="v2-toolbar-btn"
    title="Locate target hub"
    @click="navigateToHub"
  >
    <Crosshair class="size-3.5" />
  </button>
</template>
