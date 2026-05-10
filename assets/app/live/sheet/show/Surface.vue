<script setup lang="ts">
import CollabToast from "@modules/sheets/components/collab/CollabToast.vue";
import BlockList from "@modules/sheets/components/entities/blocks/BlockList.vue";
import SheetTabs from "@modules/sheets/components/panels/tabs/SheetTabs.vue";

interface SheetSurfaceTabs {
  currentTab: string;
  canEdit: boolean;
  compact: boolean;
}

interface SheetSurfaceContent {
  blocks: unknown[];
  inheritedGroups: unknown[];
  workspaceSlug: string;
  projectSlug: string;
  canEdit: boolean;
  formulaEditing: unknown;
  blockLocks: Record<string, unknown>;
  currentUserId: number | null;
}

interface SheetSurface {
  tabs: SheetSurfaceTabs;
  content: SheetSurfaceContent | null;
}

const { surface } = defineProps<{
  surface: SheetSurface;
}>();
</script>

<template>
  <div class="contents">
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
  </div>
</template>
