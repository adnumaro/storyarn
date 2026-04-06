<script setup lang="ts">
import type { Component } from "vue";
import { LayoutDashboard, Pin, X } from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { useLive } from "@composables/useLive";
import Sidebar from "./Sidebar.vue";
import SheetTree from "@modules/sheets/components/tree/SheetTree.vue";
import FlowTree from "@modules/flows/components/FlowTree.vue";
import SceneTreePanel from "@modules/scenes/components/SceneTreePanel.vue";

const treeComponents: Record<string, Component> = {
  sheets: SheetTree,
  flows: FlowTree,
  scenes: SceneTreePanel,
};

const {
  treePanelOpen = false,
  treePanelPinned = true,
  showPin = true,
  activeTool = "sheets",
  dashboardUrl = null,
  onDashboard = false,
  treeData = null,
  treeProps = {},
} = defineProps<{
  treePanelOpen?: boolean;
  treePanelPinned?: boolean;
  showPin?: boolean;
  activeTool?: string;
  dashboardUrl?: string | null;
  onDashboard?: boolean;
  treeData?: unknown[] | Record<string, string | number | boolean | null> | null;
  treeProps?: Record<string, string | number | boolean | unknown[] | null | undefined>;
}>();

const activeTreeComponent = computed(() => treeComponents[activeTool] || null);

const live = useLive();
const internalOpen = ref(false);

// ── localStorage persistence (same keys as v1 TreePanel hook) ──
const KEY_PREFIX = "storyarn:tree_panel:pinned:";
const DEFAULTS = {
  dashboard: true,
  sheets: true,
  screenplays: true,
  flows: false,
  scenes: false,
};

function storageKey(tool) {
  return `${KEY_PREFIX}${tool}`;
}

function readPinned(tool) {
  const stored = localStorage.getItem(storageKey(tool));
  if (stored !== null) return stored === "true";
  return DEFAULTS[tool] ?? true;
}

// ── Lifecycle ──
onMounted(() => {
  localStorage.removeItem("storyarn:tree_panel:pinned");

  const tool = activeTool;
  const pinned = readPinned(tool);

  if (pinned || treePanelOpen) {
    internalOpen.value = true;
  }

  live.pushEvent("tree_panel_init", { pinned });
});

// ── Watch for server-driven open/close changes ──
watch(
  () => [treePanelOpen, treePanelPinned],
  ([nowOpen, pinned]) => {
    const tool = activeTool;
    localStorage.setItem(storageKey(tool), String(pinned));
    internalOpen.value = nowOpen;
  },
);

// ── Dashboard link label ──
const toolLabels = {
  dashboard: "Dashboard",
  sheets: "Sheets",
  flows: "Flows",
  scenes: "Scenes",
  screenplays: "Screenplays",
  assets: "Assets",
  localization: "Localization",
};

const dashboardLabel = computed(() => {
  const label = toolLabels[activeTool] || "";
  return `${label} dashboard`;
});

function togglePanel() {
  live.pushEvent("tree_panel_toggle", {});
}

function togglePin() {
  live.pushEvent("tree_panel_pin", {});
}
</script>

<template>
  <Sidebar side="left" :open="internalOpen">
    <template #header>
      <div v-if="dashboardUrl" class="px-2 pt-2 pb-2">
        <a
          :href="dashboardUrl"
          :class="[
            'flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors',
            onDashboard
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-muted-foreground hover:text-foreground hover:bg-accent/50',
          ]"
        >
          <LayoutDashboard class="size-4" />
          {{ dashboardLabel }}
        </a>
      </div>
    </template>

    <component v-if="activeTreeComponent" :is="activeTreeComponent" v-bind="treeProps" />
    <slot v-else />

    <template v-if="showPin" #footer>
      <button
        type="button"
        :class="[
          'inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs transition-colors hover:bg-accent',
          treePanelPinned ? 'text-primary' : 'text-muted-foreground',
        ]"
        :title="treePanelPinned ? 'Unpin panel' : 'Pin panel'"
        @click="togglePin"
      >
        <Pin class="size-3" />
        {{ treePanelPinned ? "Pinned" : "Pin" }}
      </button>
      <button
        type="button"
        class="inline-flex items-center justify-center size-6 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
        title="Close panel"
        @click="togglePanel"
      >
        <X class="size-3" />
      </button>
    </template>
  </Sidebar>
</template>
