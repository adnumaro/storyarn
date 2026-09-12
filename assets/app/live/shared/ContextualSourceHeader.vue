<script setup lang="ts">
import FlowHeader from "@app/live/flow/show/FlowHeader.vue";
import SheetHeader from "@app/live/sheet/show/SheetHeader.vue";
import SceneHeader from "@app/live/scene/show/SceneHeader.vue";
import ExplorationLauncher from "@app/live/ideation/ExplorationLauncher.vue";
import type { ExplorationLauncherState } from "@app/live/ideation/explorationTypes";

const headers = { sheet: SheetHeader, flow: FlowHeader, scene: SceneHeader };
type HeaderProps =
  | InstanceType<typeof SheetHeader>["$props"]
  | InstanceType<typeof FlowHeader>["$props"]
  | InstanceType<typeof SceneHeader>["$props"];

const { sourceType, header, explorationState, explorationSourceKey } = defineProps<{
  sourceType: keyof typeof headers;
  header: HeaderProps;
  explorationState: ExplorationLauncherState;
  explorationSourceKey: string;
}>();
</script>

<template>
  <div class="flex h-8 min-w-0 flex-1 items-center gap-2">
    <ExplorationLauncher :state="explorationState" :source-key="explorationSourceKey" compact />
    <component :is="headers[sourceType]" v-bind="header" class="min-w-0 flex-1" />
  </div>
</template>
