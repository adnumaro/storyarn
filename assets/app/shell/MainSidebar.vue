<script setup lang="ts">
import SidebarFrame from "./SidebarFrame.vue";

defineOptions({ inheritAttrs: false });

const {
  mainSidebarOpen = false,
  activeTool = "sheets",
  dashboardUrl = null,
  onDashboard = false,
} = defineProps<{
  mainSidebarOpen?: boolean;
  activeTool?: string;
  dashboardUrl?: string | null;
  onDashboard?: boolean;
}>();
</script>

<template>
  <SidebarFrame
    :main-sidebar-open="mainSidebarOpen"
    :active-tool="activeTool"
    :dashboard-url="dashboardUrl"
    :on-dashboard="onDashboard"
  >
    <slot />
  </SidebarFrame>
</template>
