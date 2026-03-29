<script setup>
import { PlayIcon } from "lucide-vue-next";
import { ToolbarSeparator } from "@/vue/components/shared/toolbar/index.js";
import { Badge } from "@/vue/components/ui/badge/index.js";

defineProps({
	referencingFlows: { type: Array, default: () => [] },
});
</script>

<template>
  <component :is="PlayIcon" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <span class="text-xs font-medium opacity-70">Entry point</span>
  <Badge v-if="referencingFlows.length > 0" variant="secondary" class="text-[10px] px-1.5 py-0 rounded-full">
    {{ referencingFlows.length }} ref{{ referencingFlows.length === 1 ? '' : 's' }}
  </Badge>
</template>
