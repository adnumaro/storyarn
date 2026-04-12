<script setup lang="ts">
import { GitBranch, Settings } from "lucide-vue-next";
import { ToolbarSeparator } from "@components/toolbar/index.ts";
import { Badge } from "@components/ui/badge/index.ts";
import { useLive } from "@composables/useLive";
import type { Condition } from "../../types";
import type { NodeData } from "../../lib/node-configs";

interface ConditionToolbarData extends NodeData {
  switch_mode?: boolean;
  condition?: Condition;
}

const { nodeData } = defineProps<{
  nodeData: ConditionToolbarData;
}>();

const live = useLive();

function toggleSwitchMode() {
  live.pushEvent("toggle_switch_mode", {});
}

function openBuilder() {
  live.pushEvent("open_builder", {});
}
</script>

<template>
  <component :is="GitBranch" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <button type="button" class="toolbar-btn text-xs" @click="toggleSwitchMode">
    {{ nodeData.switch_mode ? "Routes" : "Multi" }}
  </button>
  <Badge
    v-if="nodeData.condition?.rules?.length"
    variant="secondary"
    class="text-[10px] px-1.5 py-0 rounded-full"
  >
    {{ nodeData.condition.rules.length }} rule{{ nodeData.condition.rules.length === 1 ? "" : "s" }}
  </Badge>
  <ToolbarSeparator />
  <button type="button" class="toolbar-btn" title="Edit condition" @click="openBuilder">
    <Settings class="size-3.5" />
  </button>
</template>
