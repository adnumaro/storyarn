<script setup lang="ts">
import SceneToolbar from "@modules/scenes/editor/components/chrome/header/SceneToolbar.vue";
import SceneHealthStatus from "@modules/scenes/editor/components/chrome/header/SceneHealthStatus.vue";
import SceneCommentsHeaderControls from "@modules/scenes/editor/components/chrome/header/SceneCommentsHeaderControls.vue";
import SearchPanel from "@modules/scenes/editor/components/chrome/header/SearchPanel.vue";
import type { SceneHealth } from "@modules/scenes/types/health";

interface SearchResult {
  id: number | string;
  type: string;
  label: string;
}

interface SceneHeaderToolbar {
  canEdit: boolean;
  sceneName: string;
  sceneShortcut: string;
}

interface SceneHeaderSearch {
  searchQuery: string;
  searchFilter: string;
  searchResults: SearchResult[];
}

interface SceneHeader {
  toolbar: SceneHeaderToolbar;
  search: SceneHeaderSearch;
  health: SceneHealth;
  comments?: { count: number; open: boolean; placing?: boolean; canComment?: boolean };
}

const { header } = defineProps<{
  header: SceneHeader;
}>();
</script>

<template>
  <div class="flex items-stretch gap-2 h-8">
    <div id="scene-toolbar" class="contents">
      <SceneToolbar
        :can-edit="header.toolbar.canEdit"
        :scene-name="header.toolbar.sceneName"
        :scene-shortcut="header.toolbar.sceneShortcut"
      />
    </div>

    <div id="scene-search-panel" class="contents">
      <SearchPanel
        :search-query="header.search.searchQuery"
        :search-filter="header.search.searchFilter"
        :search-results="header.search.searchResults"
      />
    </div>

    <SceneHealthStatus :health="header.health" />

    <SceneCommentsHeaderControls
      :count="header.comments?.count ?? 0"
      :open="header.comments?.open ?? false"
      :placing="header.comments?.placing ?? false"
      :can-comment="header.comments?.canComment ?? false"
    />
  </div>
</template>
