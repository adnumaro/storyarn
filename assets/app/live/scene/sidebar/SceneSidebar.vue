<script setup lang="ts">
import { computed } from "vue";
import SidebarFrame from "@shell/SidebarFrame.vue";
import SceneTreePanel from "@modules/scenes/editor/components/chrome/tree/SceneTreePanel.vue";

const {
  mainSidebarOpen = false,
  activeTool = "scenes",
  dashboardUrl = null,
  onDashboard = false,
  sidebarProps = {},
} = defineProps<{
  mainSidebarOpen?: boolean;
  activeTool?: string;
  dashboardUrl?: string | null;
  onDashboard?: boolean;
  sidebarProps?: Record<string, unknown>;
}>();

const sceneTreeProps = computed(
  () => sidebarProps as unknown as InstanceType<typeof SceneTreePanel>["$props"],
);
</script>

<template>
  <SidebarFrame
    :main-sidebar-open="mainSidebarOpen"
    :active-tool="activeTool"
    :dashboard-url="dashboardUrl"
    :on-dashboard="onDashboard"
  >
    <SceneTreePanel v-bind="sceneTreeProps" />
  </SidebarFrame>
</template>
