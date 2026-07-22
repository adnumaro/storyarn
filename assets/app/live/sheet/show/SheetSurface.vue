<script setup lang="ts">
import { computed } from "vue";
import { useLiveVue } from "live_vue";
import CollabToast from "@modules/sheets/components/collab/CollabToast.vue";
import SheetContentHeader from "@modules/sheets/components/chrome/header/SheetContentHeader.vue";
import BlockList from "@modules/sheets/components/entities/blocks/BlockList.vue";
import SheetShowPanels from "@modules/sheets/components/panels/SheetShowPanels.vue";
import SheetTabs from "@modules/sheets/components/panels/tabs/SheetTabs.vue";
import type { Sheet, SheetHealth } from "@modules/sheets/types";

type ServerPayload = any;

interface SheetSurfaceTabs {
  currentTab: string;
  canEdit: boolean;
  compact: boolean;
}

interface SheetSurfaceContent {
  blocks: ServerPayload[];
  inheritedGroups: ServerPayload[];
  workspaceSlug: string;
  projectSlug: string;
  canEdit: boolean;
  formulaEditing: ServerPayload;
  blockLocks: Record<string, ServerPayload>;
  currentUserId: number | null;
}

interface SheetSurface {
  tabs: SheetSurfaceTabs;
  content: SheetSurfaceContent | null;
}

interface SheetPanelsProps {
  currentTab: string;
  compact: boolean;
  references: ServerPayload | null;
  audio: ServerPayload | null;
  history: ServerPayload | null;
}

const {
  sheet: initialSheet = null,
  canEdit: initialCanEdit = false,
  sourceShortcut: initialSourceShortcut = null,
  sheetHealth: initialSheetHealth = { errorItems: [], warningItems: [], infoItems: [] },
  surface: initialSurface,
  panels: initialPanels = null,
} = defineProps<{
  sheet?: Sheet | null;
  canEdit?: boolean;
  sourceShortcut?: string | null;
  sheetHealth?: SheetHealth;
  surface: SheetSurface;
  panels?: SheetPanelsProps | null;
}>();

const live = useLiveVue();

// Injected LiveVue boundaries stay mounted while LiveView diffs replace props.
const sheet = computed(() => (live.vue?.props?.sheet as Sheet | null | undefined) ?? initialSheet);
const canEdit = computed(() => (live.vue?.props?.canEdit as boolean | undefined) ?? initialCanEdit);
const sourceShortcut = computed(
  () => (live.vue?.props?.sourceShortcut as string | null | undefined) ?? initialSourceShortcut,
);
const sheetHealth = computed(
  () => (live.vue?.props?.sheetHealth as SheetHealth | undefined) ?? initialSheetHealth,
);
const surface = computed(
  () => (live.vue?.props?.surface as SheetSurface | undefined) ?? initialSurface,
);
const panels = computed(
  () => (live.vue?.props?.panels as SheetPanelsProps | null | undefined) ?? initialPanels,
);
</script>

<template>
  <div
    v-if="sheet"
    class="max-w-4xl mx-auto bg-surface border border-border rounded-2xl p-6 shadow-sm"
  >
    <SheetContentHeader
      :sheet="sheet"
      :can-edit="canEdit"
      :source-shortcut="sourceShortcut"
      :sheet-health="sheetHealth"
    />

    <div class="pb-6">
      <div id="sheet-tabs" class="contents">
        <SheetTabs
          :current-tab="surface.tabs.currentTab"
          :can-edit="surface.tabs.canEdit"
          :compact="surface.tabs.compact"
        />
      </div>

      <div v-if="surface.content" id="block-list" class="contents">
        <BlockList
          :blocks="surface.content.blocks"
          :inherited-groups="surface.content.inheritedGroups"
          :workspace-slug="surface.content.workspaceSlug"
          :project-slug="surface.content.projectSlug"
          :can-edit="surface.content.canEdit"
          :formula-editing="surface.content.formulaEditing"
          :block-locks="surface.content.blockLocks"
          :current-user-id="surface.content.currentUserId"
        />
      </div>

      <div id="collab-toast" class="contents">
        <CollabToast />
      </div>

      <SheetShowPanels v-if="panels" :panels="panels" />
    </div>
  </div>

  <div v-else class="flex justify-center py-20">
    <div
      class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
    />
  </div>
</template>
