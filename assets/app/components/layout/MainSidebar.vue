<script setup lang="ts">
import type { Component } from "vue";
import { LayoutDashboard, Pin, X } from "lucide-vue-next";
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { useLive } from "@composables/useLive";
import Sidebar from "./Sidebar.vue";
import SheetTree from "@modules/sheets/components/tree/SheetTree.vue";
import FlowTree from "@modules/flows/components/FlowTree.vue";
import SceneTreePanel from "@modules/scenes/components/SceneTreePanel.vue";
import LocalizationSidebar from "@modules/localization/components/LocalizationSidebar.vue";

const sidebarComponents: Record<string, Component> = {
  sheets: SheetTree,
  flows: FlowTree,
  scenes: SceneTreePanel,
  localization: LocalizationSidebar,
};

const {
  mainSidebarOpen = false,
  mainSidebarPinned = true,
  showPin = true,
  activeTool = "sheets",
  dashboardUrl = null,
  onDashboard = false,
  sidebarData = null,
  sidebarProps = {},
} = defineProps<{
  mainSidebarOpen?: boolean;
  mainSidebarPinned?: boolean;
  showPin?: boolean;
  activeTool?: string;
  dashboardUrl?: string | null;
  onDashboard?: boolean;
  sidebarData?: unknown[] | Record<string, string | number | boolean | null> | null;
  sidebarProps?: Record<string, string | number | boolean | unknown[] | null | undefined>;
}>();

const activeSidebarContent = computed(() => sidebarComponents[activeTool] || null);

const live = useLive();
const internalOpen = ref(false);

const KEY_PREFIX = "storyarn:main_sidebar:pinned:";
const DEFAULTS = {
  dashboard: true,
  sheets: true,
  screenplays: true,
  flows: false,
  scenes: false,
};

function storageKey(tool: string) {
  return `${KEY_PREFIX}${tool}`;
}

function readPinned(tool: string) {
  const stored = localStorage.getItem(storageKey(tool));
  if (stored !== null) return stored === "true";
  return DEFAULTS[tool as keyof typeof DEFAULTS] ?? true;
}

onMounted(() => {
  const tool = activeTool;
  const pinned = readPinned(tool);

  if (pinned || mainSidebarOpen) {
    internalOpen.value = true;
  }

  live.pushEvent("main_sidebar_init", { pinned });
});

watch(
  () => [mainSidebarOpen, mainSidebarPinned],
  ([nowOpen, pinned]) => {
    const tool = activeTool;
    localStorage.setItem(storageKey(tool), String(pinned));
    internalOpen.value = nowOpen;
  },
);

// ProjectShell's <main> reads `body[data-main-sidebar-open="1"]` in CSS to
// apply the left padding when the panel is open (and remove it when closed).
watch(
  internalOpen,
  (open) => {
    if (open) {
      document.body.dataset.mainSidebarOpen = "1";
    } else {
      delete document.body.dataset.mainSidebarOpen;
    }
  },
  { immediate: true },
);

onUnmounted(() => {
  delete document.body.dataset.mainSidebarOpen;
});
function togglePanel() {
  live.pushEvent("main_sidebar_toggle", {});
}
function togglePin() {
  live.pushEvent("main_sidebar_pin", {});
}
</script>

<template>
  <Sidebar side="left" :open="internalOpen">
    <template #header>
      <div v-if="dashboardUrl" class="pt-2 pb-2">
        <a
          :href="dashboardUrl"
          data-phx-link="patch"
          data-phx-link-state="push"
          :class="[
            'flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors',
            onDashboard
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-muted-foreground hover:text-foreground hover:bg-accent/50',
          ]"
        >
          <LayoutDashboard class="size-4" />
          {{
            $t("layout.main_sidebar.dashboard_label", { tool: $t(`layout.tools.${activeTool}`) })
          }}
        </a>
      </div>
    </template>

    <component v-if="activeSidebarContent" :is="activeSidebarContent" v-bind="sidebarProps" />
    <slot v-else />

    <template v-if="showPin" #footer>
      <button
        type="button"
        :class="[
          'inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs transition-colors hover:bg-accent',
          mainSidebarPinned ? 'text-primary' : 'text-muted-foreground',
        ]"
        :title="
          mainSidebarPinned ? $t('layout.main_sidebar.unpin') : $t('layout.main_sidebar.pin_panel')
        "
        @click="togglePin"
      >
        <Pin class="size-3" />
        {{ mainSidebarPinned ? $t("layout.main_sidebar.pinned") : $t("layout.main_sidebar.pin") }}
      </button>
      <button
        type="button"
        class="inline-flex items-center justify-center size-6 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
        :title="$t('layout.main_sidebar.close')"
        @click="togglePanel"
      >
        <X class="size-3" />
      </button>
    </template>
  </Sidebar>
</template>
