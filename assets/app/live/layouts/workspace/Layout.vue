<script setup lang="ts">
import WorkspaceSidebar from "@shell/WorkspaceSidebar.vue";
import type { WorkspaceItem, WorkspaceUser } from "@shell/workspaceLayoutTypes";
import { useMediaQuery } from "@shared/composables/useMediaQuery";

const {
  currentUser,
  workspaces = [],
  currentWorkspaceSlug = null,
} = defineProps<{
  currentUser: WorkspaceUser;
  workspaces?: WorkspaceItem[];
  currentWorkspaceSlug?: string | null;
}>();

const sidebarOpen = useMediaQuery("(min-width: 1024px)");
</script>

<template>
  <div class="relative h-screen w-screen overflow-hidden bg-surface">
    <aside
      :aria-hidden="!sidebarOpen"
      :inert="!sidebarOpen"
      class="absolute inset-y-0 left-0 z-0 w-[calc(100vw-4rem)] sm:w-63 overflow-hidden"
    >
      <WorkspaceSidebar
        id="workspace-sidebar"
        :current-user="currentUser"
        class="h-full overflow-hidden"
        :workspaces="workspaces"
        :current-workspace-slug="currentWorkspaceSlug"
      />
    </aside>

    <main
      id="main-content"
      :class="[
        'relative z-10 h-full min-dvh-100 w-full bg-background transition-[transform,width,border-radius,box-shadow] duration-300 ease-out will-change-transform flex flex-col overflow-hidden',
        sidebarOpen
          ? 'translate-x-[calc(100vw-4rem)] sm:translate-x-63 sm:w-[calc(100%-15.75rem)] shadow-xl rounded-l-2xl'
          : 'translate-x-0',
      ]"
    >
      <div class="flex-1 min-h-0 overflow-y-auto p-4 lg:px-6 lg:py-6">
        <slot />
      </div>
    </main>
  </div>
</template>
