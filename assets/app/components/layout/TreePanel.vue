<script setup>
import { LayoutDashboard, Pin, X } from "lucide-vue-next";
import { computed, defineAsyncComponent, onMounted, ref, watch } from "vue";
import { useLive } from "@composables/useLive";
import Sidebar from "./Sidebar.vue";

const treeComponents = {
  sheets: defineAsyncComponent(
    () => import("@pages/workspaces/projects/sheets/components/tree/SheetTree.vue"),
  ),
  flows: defineAsyncComponent(
    () => import("@pages/workspaces/projects/flows/components/FlowTree.vue"),
  ),
  scenes: defineAsyncComponent(
    () => import("@pages/workspaces/projects/scenes/components/SceneTreePanel.vue"),
  ),
};

const props = defineProps({
  treePanelOpen: { type: Boolean, default: false },
  treePanelPinned: { type: Boolean, default: true },
  showPin: { type: Boolean, default: true },
  activeTool: { type: String, default: "sheets" },
  dashboardUrl: { type: String, default: null },
  onDashboard: { type: Boolean, default: false },
  treeData: { type: [Array, Object], default: null },
  treeProps: { type: Object, default: () => ({}) },
});

const activeTreeComponent = computed(() => treeComponents[props.activeTool] || null);

const live = useLive();
const internalOpen = ref(false);

// ── localStorage persistence (same keys as v1 TreePanel hook) ──
const KEY_PREFIX = "storyarn:tree_panel:pinned:";
const DEFAULTS = {
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

  const tool = props.activeTool;
  const pinned = readPinned(tool);

  if (pinned || props.treePanelOpen) {
    internalOpen.value = true;
  }

  live.pushEvent("tree_panel_init", { pinned });
});

// ── Watch for server-driven open/close changes ──
watch(
  () => [props.treePanelOpen, props.treePanelPinned],
  ([nowOpen, pinned]) => {
    const tool = props.activeTool;
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
  const label = toolLabels[props.activeTool] || "";
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
