<script setup lang="ts">
import WorkspaceSidebar from "@shell/WorkspaceSidebar.vue";
import type { WorkspaceItem, WorkspaceUser } from "@shell/workspaceLayoutTypes";

const {
  currentUser,
  workspaces = [],
  currentWorkspaceSlug,
} = defineProps<{
  currentUser: WorkspaceUser;
  workspaces?: WorkspaceItem[];
  currentWorkspaceSlug: string;
}>();
</script>

<template>
  <div class="flex h-screen w-screen overflow-hidden">
    <input id="workspace-sidebar-check" type="checkbox" class="peer hidden" />

    <label
      for="workspace-sidebar-check"
      class="fixed inset-0 bg-background/80 backdrop-blur-sm z-30 hidden peer-checked:block lg:hidden cursor-pointer"
    />

    <aside
      :class="[
        'flex-none w-[252px] surface-panel flex flex-col z-40 shrink-0 overflow-hidden rounded-lg',
        'fixed lg:relative top-3 bottom-3 left-3 lg:top-0 lg:bottom-0 lg:left-0 h-[calc(100vh-1.5rem)] lg:h-auto',
        'lg:ml-3 lg:my-3',
        'transition-transform duration-200',
        '-translate-x-[calc(100%+1rem)] peer-checked:translate-x-0 lg:translate-x-0',
      ]"
    >
      <WorkspaceSidebar
        id="workspace-sidebar"
        :current-user="currentUser"
        class="h-full"
        :workspaces="workspaces"
        :current-workspace-slug="currentWorkspaceSlug"
      />
    </aside>

    <main id="main-content" class="overflow-y-auto p-4 lg:px-8 lg:py-3 min-dvh-100 w-full">
      <slot />
    </main>
  </div>
</template>
