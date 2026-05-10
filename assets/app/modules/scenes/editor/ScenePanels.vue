<script setup lang="ts">
import ElementPropertiesPanel from "./components/panels/ElementPropertiesPanel.vue";
import SettingsPanel from "./components/panels/SettingsPanel.vue";
import VersionHistoryPanel from "./components/panels/VersionHistoryPanel.vue";

interface SceneVersionsPanel {
  open: boolean;
  versions: unknown[];
  namedVersions: unknown[];
  autoVersions: unknown[];
  hasMore: boolean;
  canNameVersion: boolean;
  currentVersionId: number | null;
  canEdit: boolean;
  loading: boolean;
}

interface SceneElementPanel {
  selectedType: string | null;
  selectedElement: unknown;
  canEdit: boolean;
  elementPanelOpen: boolean;
  projectSheets: unknown[];
  projectFlows: unknown[];
  projectScenes: unknown[];
  projectVariables: unknown[];
}

interface SceneSettingsPanel {
  scene: unknown;
  canEdit: boolean;
  ambientFlows: unknown[];
  projectFlows: unknown[];
  sceneSettingsOpen: boolean;
}

interface ScenePanels {
  versions: SceneVersionsPanel;
  element: SceneElementPanel;
  settings: SceneSettingsPanel;
}

const { panels } = defineProps<{
  panels: ScenePanels;
}>();
</script>

<template>
  <div class="contents">
    <div id="scene-versions-panel" class="contents">
      <VersionHistoryPanel
        :open="panels.versions.open"
        :versions="panels.versions.versions"
        :named-versions="panels.versions.namedVersions"
        :auto-versions="panels.versions.autoVersions"
        :has-more="panels.versions.hasMore"
        :can-name-version="panels.versions.canNameVersion"
        :current-version-id="panels.versions.currentVersionId"
        :can-edit="panels.versions.canEdit"
        :loading="panels.versions.loading"
      />
    </div>

    <div id="scene-element-panel-vue" class="contents">
      <ElementPropertiesPanel
        :selected-type="panels.element.selectedType"
        :selected-element="panels.element.selectedElement"
        :can-edit="panels.element.canEdit"
        :element-panel-open="panels.element.elementPanelOpen"
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
        :scene-settings-open="panels.settings.sceneSettingsOpen"
      />
    </div>
  </div>
</template>
