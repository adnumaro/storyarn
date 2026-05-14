<script setup lang="ts">
import SidebarFrame from "@shell/SidebarFrame.vue";
import LocalizationSidebar from "@modules/localization/components/chrome/LocalizationSidebar.vue";

const {
  mainSidebarOpen = false,
  activeTool = "localization",
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
    <LocalizationSidebar v-bind="sidebarProps" />
  </SidebarFrame>
</template>
