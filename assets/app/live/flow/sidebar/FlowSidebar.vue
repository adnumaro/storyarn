<script setup lang="ts">
import SidebarFrame from "@shell/SidebarFrame.vue";
import FlowTree from "@modules/flows/editor/components/chrome/tree/FlowTree.vue";

const {
  mainSidebarOpen = false,
  activeTool = "flows",
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
</script>

<template>
  <SidebarFrame
    :main-sidebar-open="mainSidebarOpen"
    :active-tool="activeTool"
    :dashboard-url="dashboardUrl"
    :on-dashboard="onDashboard"
  >
    <FlowTree v-bind="sidebarProps" />
  </SidebarFrame>
</template>
