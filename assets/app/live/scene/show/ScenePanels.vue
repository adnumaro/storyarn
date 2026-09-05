<script setup lang="ts">
import { computed } from "vue";
import ElementPropertiesPanel from "@modules/scenes/editor/components/panels/ElementPropertiesPanel.vue";
import SceneCommentsPanel from "@modules/scenes/editor/components/panels/SceneCommentsPanel.vue";
import SettingsPanel from "@modules/scenes/editor/components/panels/SettingsPanel.vue";
import VersionHistoryPanel from "@modules/scenes/editor/components/panels/VersionHistoryPanel.vue";
import type { SceneCommentsPanelState } from "@modules/scenes/types/comments";

type ServerPayload = any;

interface SceneVersionsPanel {
  open: boolean;
  versions: ServerPayload[];
  namedVersions: ServerPayload[];
  autoVersions: ServerPayload[];
  hasMore: boolean;
  canNameVersion: boolean;
  currentVersionId: number | null;
  canEdit: boolean;
  restoreEnabled: boolean;
  loading: boolean;
}

interface SceneElementPanel {
  selectedType: string | null;
  selectedElement: ServerPayload;
  canEdit: boolean;
  elementPanelOpen: boolean;
  projectSheets: ServerPayload[];
  projectFlows: ServerPayload[];
  projectScenes: ServerPayload[];
  projectVariables: ServerPayload[];
}

interface SceneSettingsPanel {
  scene: ServerPayload;
  canEdit: boolean;
  ambientFlows: ServerPayload[];
  projectFlows: ServerPayload[];
  sceneSettingsOpen: boolean;
}

interface ScenePanels {
  comments?: SceneCommentsPanelState;
  versions: SceneVersionsPanel;
  element: SceneElementPanel;
  settings: SceneSettingsPanel;
}

const { panels } = defineProps<{
  panels: ScenePanels;
}>();

const commentsPanelOpen = computed(
  () => panels.comments?.open && panels.comments.presentation !== "canvas",
);
</script>

<template>
  <div class="contents">
    <div v-if="panels.comments" id="scene-comments-panel" class="contents">
      <SceneCommentsPanel :state="panels.comments" />
    </div>

    <div id="scene-versions-panel" class="contents">
      <VersionHistoryPanel
        :open="panels.versions.open && !commentsPanelOpen"
        :versions="panels.versions.versions"
        :named-versions="panels.versions.namedVersions"
        :auto-versions="panels.versions.autoVersions"
        :has-more="panels.versions.hasMore"
        :can-name-version="panels.versions.canNameVersion"
        :current-version-id="panels.versions.currentVersionId"
        :can-edit="panels.versions.canEdit"
        :restore-enabled="panels.versions.restoreEnabled"
        :loading="panels.versions.loading"
      />
    </div>

    <div id="scene-element-panel-vue" class="contents">
      <ElementPropertiesPanel
        :selected-type="panels.element.selectedType"
        :selected-element="panels.element.selectedElement"
        :can-edit="panels.element.canEdit"
        :element-panel-open="panels.element.elementPanelOpen && !commentsPanelOpen"
        :project-sheets="panels.element.projectSheets"
        :project-flows="panels.element.projectFlows"
        :project-scenes="panels.element.projectScenes"
        :project-variables="panels.element.projectVariables"
      />
    </div>

    <div id="scene-settings-vue" class="contents">
      <SettingsPanel
        :scene="panels.settings.scene"
        :can-edit="panels.settings.canEdit"
        :ambient-flows="panels.settings.ambientFlows"
        :project-flows="panels.settings.projectFlows"
        :scene-settings-open="panels.settings.sceneSettingsOpen && !commentsPanelOpen"
      />
    </div>
  </div>
</template>
