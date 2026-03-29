<script setup>
import { Settings, Zap } from "lucide-vue-next";
import { ToolbarSeparator } from "@/vue/components/shared/toolbar/index.js";
import { Badge } from "@/vue/components/ui/badge/index.js";
import { useLive } from "@/vue/composables/useLive.js";

defineProps({
	nodeData: { type: Object, required: true },
});

const live = useLive();

function openBuilder() {
	live.pushEvent("open_builder", {});
}
</script>

<template>
  <component :is="Zap" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <Badge v-if="nodeData.assignments?.length" variant="secondary" class="text-[10px] px-1.5 py-0 rounded-full">
    {{ nodeData.assignments.length }} assignment{{ nodeData.assignments.length === 1 ? '' : 's' }}
  </Badge>
  <ToolbarSeparator />
  <button type="button" class="v2-toolbar-btn" title="Edit instructions" @click="openBuilder">
    <Settings class="size-3.5" />
  </button>
</template>
