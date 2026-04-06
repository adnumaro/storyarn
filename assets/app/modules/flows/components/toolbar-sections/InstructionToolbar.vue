<script setup lang="ts">
import { Settings, Zap } from "lucide-vue-next";
import { ToolbarSeparator } from "@components/toolbar/index.ts";
import { Badge } from "@components/ui/badge/index.ts";
import { useLive } from "@composables/useLive";
import type { InstructionAssignment } from "../../types";
import type { NodeData } from "../../lib/node-configs";

interface InstructionToolbarData extends NodeData {
  assignments?: InstructionAssignment[];
}

const { nodeData } = defineProps<{
  nodeData: InstructionToolbarData;
}>();

const live = useLive();

function openBuilder() {
  live.pushEvent("open_builder", {});
}
</script>

<template>
  <component :is="Zap" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <Badge
    v-if="nodeData.assignments?.length"
    variant="secondary"
    class="text-[10px] px-1.5 py-0 rounded-full"
  >
    {{ nodeData.assignments.length }} assignment{{ nodeData.assignments.length === 1 ? "" : "s" }}
  </Badge>
  <ToolbarSeparator />
  <button type="button" class="v2-toolbar-btn" title="Edit instructions" @click="openBuilder">
    <Settings class="size-3.5" />
  </button>
</template>
