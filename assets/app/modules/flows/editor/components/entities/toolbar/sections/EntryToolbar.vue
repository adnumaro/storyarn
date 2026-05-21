<script setup lang="ts">
import { PlayIcon } from "lucide-vue-next";
import { ToolbarSeparator } from "@components/toolbar";
import { Badge } from "@components/ui/badge";
import type { ReferencingFlow } from "../../../../../types";

defineOptions({ inheritAttrs: false });

const { referencingFlows = [] } = defineProps<{
  referencingFlows?: ReferencingFlow[];
}>();
</script>

<template>
  <component :is="PlayIcon" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <span class="text-xs font-medium opacity-70">{{ $t("flows.entry_toolbar.entry_point") }}</span>
  <Badge
    v-if="referencingFlows.length > 0"
    variant="secondary"
    class="text-[10px] px-1.5 py-0 rounded-full"
  >
    {{ $t("flows.entry_toolbar.refs", referencingFlows.length) }}
  </Badge>
</template>
