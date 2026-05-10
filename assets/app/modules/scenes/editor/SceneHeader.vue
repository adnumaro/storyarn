<script setup lang="ts">
import SceneToolbar from "./components/chrome/header/SceneToolbar.vue";
import SearchPanel from "./components/chrome/header/SearchPanel.vue";

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
  </div>
</template>
