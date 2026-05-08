<script setup lang="ts">
import SidebarFrame from "@shell/SidebarFrame.vue";
import FlowTree from "../editor/components/chrome/tree/FlowTree.vue";

const {
  mainSidebarOpen = false,
  mainSidebarPinned = true,
  showPin = true,
  activeTool = "flows",
  dashboardUrl = null,
  onDashboard = false,
  sidebarProps = {},
} = defineProps<{
  mainSidebarOpen?: boolean;
  mainSidebarPinned?: boolean;
  showPin?: boolean;
  activeTool?: string;
  dashboardUrl?: string | null;
  onDashboard?: boolean;
  sidebarProps?: Record<string, unknown>;
}>();
</script>

<template>
  <SidebarFrame
    :main-sidebar-open="mainSidebarOpen"
    :main-sidebar-pinned="mainSidebarPinned"
    :show-pin="showPin"
    :active-tool="activeTool"
    :dashboard-url="dashboardUrl"
    :on-dashboard="onDashboard"
  >
    <FlowTree v-bind="sidebarProps" />
  </SidebarFrame>
</template>
