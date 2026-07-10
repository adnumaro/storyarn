<script setup lang="ts">
import { PanelLeft, PanelLeftClose } from "lucide-vue-next";
import { ref } from "vue";
import OnboardingDialog from "@components/onboarding/OnboardingDialog.vue";
import WorkspaceSidebar from "@shell/WorkspaceSidebar.vue";
import type { WorkspaceItem, WorkspaceUser } from "@shell/workspaceLayoutTypes";
import { useResponsiveSidebar } from "@shared/composables/useResponsiveSidebar";

const {
  currentUser,
  workspaces = [],
  currentWorkspaceSlug = null,
  onboarding = null,
} = defineProps<{
  currentUser: WorkspaceUser;
  workspaces?: WorkspaceItem[];
  currentWorkspaceSlug?: string | null;
  onboarding?: { guide: string; autoShow: boolean } | null;
}>();

const { sidebarOpen, toggleSidebar } = useResponsiveSidebar();
const onboardingDialog = ref<{ openTutorial: () => void } | null>(null);

function showTutorial(): void {
  onboardingDialog.value?.openTutorial();
}
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
        :has-tutorial="Boolean(onboarding)"
        @show-tutorial="showTutorial"
      />
    </aside>

    <main
      id="main-content"
      :class="[
        'relative z-10 h-full min-dvh-100 min-w-0 w-full bg-background transition-[margin-left,width,border-radius,box-shadow] duration-300 ease-out will-change-[margin-left,width] flex flex-col overflow-hidden',
        sidebarOpen
          ? 'ml-[calc(100vw-4rem)] w-16 sm:ml-63 sm:w-[calc(100%-15.75rem)] shadow-xl rounded-l-2xl'
          : 'ml-0 w-full',
      ]"
    >
      <div
        class="flex h-12 shrink-0 items-center border-b border-border/70 bg-background/95 px-3 lg:hidden"
      >
        <button
          type="button"
          class="toolbar-btn size-9"
          :aria-label="
            sidebarOpen
              ? $t('layout.main_sidebar.hide_panel')
              : $t('layout.main_sidebar.show_panel')
          "
          :title="
            sidebarOpen
              ? $t('layout.main_sidebar.hide_panel')
              : $t('layout.main_sidebar.show_panel')
          "
          :aria-pressed="sidebarOpen"
          @click="toggleSidebar"
        >
          <PanelLeftClose v-if="sidebarOpen" class="size-4" />
          <PanelLeft v-else class="size-4" />
        </button>
      </div>

      <div class="flex-1 min-h-0 overflow-y-auto p-4 lg:px-6 lg:py-6">
        <slot />
      </div>
    </main>

    <OnboardingDialog
      v-if="onboarding"
      ref="onboardingDialog"
      :guide-key="onboarding.guide"
      :auto-show="onboarding.autoShow"
    />
  </div>
</template>
