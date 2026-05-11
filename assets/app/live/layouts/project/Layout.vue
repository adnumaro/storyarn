<script setup lang="ts">
import { onMounted, onUnmounted } from "vue";
import ProjectNavbarContext from "@shell/ProjectNavbarContext.vue";
import ProjectNavbarAccount from "@shell/ProjectNavbarAccount.vue";
import type { CurrentUser, OnlineUser, ProjectLayoutUrls } from "@shell/projectNavbarTypes";

interface ProjectChrome {
  activeTool: string;
  hasTree: boolean;
  mainSidebarOpen: boolean;
  projectName: string;
  workspaceName: string;
  showToolSwitcher: boolean;
  isSuperAdmin: boolean;
}

interface RestorationBanner {
  user_email?: string;
  userEmail?: string;
}

const {
  chrome,
  currentUser,
  onlineUsers = [],
  urls,
  restorationBanner = null,
  canvasMode = false,
} = defineProps<{
  chrome: ProjectChrome;
  currentUser: CurrentUser;
  onlineUsers?: OnlineUser[];
  urls: ProjectLayoutUrls;
  restorationBanner?: RestorationBanner | null;
  canvasMode?: boolean;
}>();

const nonCanvasMainClasses = [
  "overflow-y-auto pt-16 pb-4 px-4",
  "transition-[padding-left] duration-200",
  "md:[body[data-main-sidebar-open='1']_&]:pl-[320px]",
];

onMounted(() => {
  document.documentElement.style.setProperty("--storyarn-project-sidebar-top", "3.5rem");
});

onUnmounted(() => {
  document.documentElement.style.removeProperty("--storyarn-project-sidebar-top");
});
</script>

<template>
  <div class="h-screen w-screen overflow-hidden relative bg-background">
    <div
      v-if="restorationBanner"
      class="fixed top-0 left-0 right-0 z-42 flex justify-center pointer-events-none"
    >
      <div
        class="bg-destructive text-destructive-foreground px-4 py-2 rounded-b-lg shadow-lg flex items-center gap-2 text-sm pointer-events-auto"
      >
        <span
          class="size-4 border-2 border-current/30 border-t-current rounded-full animate-spin"
          aria-hidden="true"
        />
        <span>
          {{
            $t("layout.project_restoration.in_progress", {
              user: restorationBanner.user_email || restorationBanner.userEmail || "another user",
            })
          }}
        </span>
      </div>
    </div>

    <header
      class="project-navbar fixed inset-x-0 top-0 z-41 min-h-11.5 h-11.5 max-h-11.5 border-b border-border/70 bg-background/95 backdrop-blur supports-backdrop-filter:bg-background/85"
    >
      <div class="flex h-full min-w-0 items-center gap-2 px-3">
        <div class="flex min-w-0 flex-1 items-center gap-2 overflow-hidden">
          <div id="project-navbar-context-wrapper" class="shrink-0">
            <ProjectNavbarContext
              id="project-navbar-context"
              :active-tool="chrome.activeTool"
              :has-tree="chrome.hasTree"
              :main-sidebar-open="chrome.mainSidebarOpen"
              :project-name="chrome.projectName"
              :workspace-name="chrome.workspaceName"
              :show-tool-switcher="chrome.showToolSwitcher"
              :is-super-admin="chrome.isSuperAdmin"
              :urls="urls"
            />
          </div>

          <div class="min-w-0 flex flex-1 items-center gap-2 overflow-hidden">
            <slot name="top-left" />
          </div>
        </div>

        <div class="flex shrink-0 items-center gap-2">
          <slot name="top-right" />

          <div id="project-navbar-account-wrapper" class="shrink-0">
            <ProjectNavbarAccount
              id="project-navbar-account"
              :current-user="currentUser"
              :online-users="onlineUsers"
              :urls="urls"
            />
          </div>
        </div>
      </div>
    </header>

    <main
      id="main-content"
      :class="[
        canvasMode
          ? 'absolute inset-x-0 bottom-0 top-13.5 overflow-hidden'
          : ['h-full', nonCanvasMainClasses],
      ]"
    >
      <template v-if="canvasMode">
        <div class="h-full relative">
          <div class="absolute inset-0 flex flex-col">
            <div class="flex-1 relative">
              <slot />
            </div>

            <slot name="panels" />
          </div>
        </div>
      </template>

      <template v-else>
        <slot />
        <slot name="panels" />
      </template>
    </main>
  </div>
</template>

<style scoped>
.project-navbar :deep(.surface-panel) {
  border-color: transparent;
  background: transparent;
  box-shadow: none;
}
</style>
