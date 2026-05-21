<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
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

const sidebarOpen = ref(chrome.hasTree && chrome.mainSidebarOpen);

let desktopSidebarQuery: MediaQueryList | null = null;
function syncDesktopSidebar(query: MediaQueryList | MediaQueryListEvent): void {
  sidebarOpen.value = chrome.hasTree && query.matches;
}

function handleMainSidebarChange(event: Event) {
  sidebarOpen.value =
    chrome.hasTree && Boolean((event as CustomEvent<{ open?: boolean }>).detail?.open);
}

onMounted(() => {
  desktopSidebarQuery = window.matchMedia("(min-width: 1024px)");
  syncDesktopSidebar(desktopSidebarQuery);
  desktopSidebarQuery.addEventListener("change", syncDesktopSidebar);
  window.addEventListener("storyarn:main-sidebar-change", handleMainSidebarChange);
});

onUnmounted(() => {
  desktopSidebarQuery?.removeEventListener("change", syncDesktopSidebar);
  window.removeEventListener("storyarn:main-sidebar-change", handleMainSidebarChange);
});
</script>

<template>
  <div class="relative h-screen overflow-hidden">
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

    <div
      id="project-main-shell"
      :class="[
        'pointer-events-auto relative z-10 h-full min-w-0 w-full flex flex-col overflow-hidden bg-background transition-[margin-left,width,border-radius,box-shadow] duration-300 ease-out will-change-[margin-left,width]',
        chrome.hasTree && sidebarOpen
          ? 'ml-[calc(100vw-4rem)] w-16 sm:ml-63 sm:w-[calc(100%-15.75rem)]'
          : 'ml-0 w-full',
        chrome.hasTree && sidebarOpen && 'shadow-xl rounded-l-2xl',
      ]"
    >
      <header
        class="project-navbar relative z-41 shrink-0 min-h-13.5 h-13.5 max-h-13.5 border-b border-border/70 bg-background/95"
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
        class="relative z-10 h-full min-dvh-100 w-full bg-background flex-1 flex flex-col overflow-hidden"
      >
        <template v-if="canvasMode">
          <div class="flex-1 min-h-0 relative overflow-hidden">
            <slot />
          </div>
        </template>

        <template v-else>
          <div class="flex-1 min-h-0 overflow-y-auto p-4 lg:px-6 lg:py-6">
            <slot />
          </div>
        </template>

        <slot name="panels" />
      </main>
    </div>
  </div>
</template>
