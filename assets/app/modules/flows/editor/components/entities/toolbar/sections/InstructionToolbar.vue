<script setup lang="ts">
import { Settings, Zap } from "lucide-vue-next";
import { ToolbarSeparator } from "@components/toolbar";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Badge } from "@components/ui/badge";
import { useLive } from "../../../../../../../shared/composables/useLive";
import type { InstructionAssignment } from "../../../../../types";
import type { NodeData } from "../../../../lib/node-configs";

defineOptions({ inheritAttrs: false });

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
  <ToolbarTooltip :label="$t('flows.instruction_toolbar.edit_instructions')">
    <button type="button" class="toolbar-btn" @click="openBuilder">
      <Settings class="size-3.5" />
    </button>
  </ToolbarTooltip>
</template>
