<script setup lang="ts">
import AudioTab from "@modules/sheets/components/panels/tabs/AudioTab.vue";
import HistoryTab from "@modules/sheets/components/panels/tabs/HistoryTab.vue";
import ReferencesTab from "@modules/sheets/components/panels/tabs/ReferencesTab.vue";

interface SheetReferencesPanel {
  variableUsage: unknown[];
  backlinks: unknown[];
  sceneAppearances: unknown[];
  workspaceSlug: string;
  projectSlug: string;
  loading: boolean;
}

interface SheetAudioPanel {
  groupedLines: unknown[];
  audioAssets: unknown[];
  workspaceSlug: string;
  projectSlug: string;
  canEdit: boolean;
  loading: boolean;
}

interface SheetHistoryPanel {
  versions: unknown[];
  namedVersions: unknown[];
  autoVersions: unknown[];
  hasMore: boolean;
  canNameVersion: boolean;
  currentVersionId: number | null;
  canEdit: boolean;
  loading: boolean;
}

interface SheetPanels {
  currentTab: string;
  compact: boolean;
  references: SheetReferencesPanel | null;
  audio: SheetAudioPanel | null;
  history: SheetHistoryPanel | null;
}

const { panels } = defineProps<{
  panels: SheetPanels;
}>();
</script>

<template>
  <div class="contents">
    <div
      v-if="panels.currentTab === 'references' && panels.references"
      id="references-tab"
      class="contents"
    >
      <ReferencesTab
        :variable-usage="panels.references.variableUsage"
        :backlinks="panels.references.backlinks"
        :scene-appearances="panels.references.sceneAppearances"
        :workspace-slug="panels.references.workspaceSlug"
        :project-slug="panels.references.projectSlug"
        :loading="panels.references.loading"
      />
    </div>

    <div v-if="panels.currentTab === 'audio' && panels.audio" id="audio-tab" class="contents">
      <AudioTab
        :grouped-lines="panels.audio.groupedLines"
        :audio-assets="panels.audio.audioAssets"
        :workspace-slug="panels.audio.workspaceSlug"
        :project-slug="panels.audio.projectSlug"
        :can-edit="panels.audio.canEdit"
        :loading="panels.audio.loading"
      />
    </div>

    <div
      v-if="panels.currentTab === 'history' && panels.history && !panels.compact"
      id="history-tab"
      class="contents"
    >
      <HistoryTab
        :versions="panels.history.versions"
        :named-versions="panels.history.namedVersions"
        :auto-versions="panels.history.autoVersions"
        :has-more="panels.history.hasMore"
        :can-name-version="panels.history.canNameVersion"
        :current-version-id="panels.history.currentVersionId"
        :can-edit="panels.history.canEdit"
        :loading="panels.history.loading"
      />
    </div>
  </div>
</template>
