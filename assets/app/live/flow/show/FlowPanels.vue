<script setup lang="ts">
import FlowBuilderPanel from "@modules/flows/editor/components/panels/FlowBuilderPanel.vue";
import FlowDebugPanel from "@modules/flows/editor/components/panels/FlowDebugPanel.vue";
import FlowDialogueFullscreenEditor from "@modules/flows/editor/components/panels/FlowDialogueFullscreenEditor.vue";
import FlowDialoguePanel from "@modules/flows/editor/components/panels/FlowDialoguePanel.vue";
import FlowPreview from "@modules/flows/editor/components/panels/FlowPreview.vue";
import FlowSequenceConfigPanel from "@modules/flows/editor/components/panels/FlowSequenceConfigPanel.vue";
import FlowVersionHistoryPanel from "@modules/flows/editor/components/panels/FlowVersionHistoryPanel.vue";

interface FlowVersionsPanel {
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

interface FlowDebugPanelState {
  open: boolean;
  state: unknown;
  nodes: Record<string, unknown>;
  controls: Record<string, unknown>;
}

interface FlowBuilderPanelState {
  open: boolean;
  nodeType: string | null;
  nodeId: number | string | null;
  condition: unknown;
  assignments: unknown[] | null;
  switchMode: boolean | null;
  projectVariables: string;
  canEdit: boolean;
}

interface FlowPanelState {
  open: boolean;
  data: unknown;
  canEdit: boolean;
}

interface FlowPreviewPanel {
  open: boolean;
  currentNode: unknown;
  responses: unknown[];
  hasNext: boolean;
  hasHistory: boolean;
}

interface FlowPanels {
  versions: FlowVersionsPanel;
  debug: FlowDebugPanelState;
  builder: FlowBuilderPanelState;
  dialogue: FlowPanelState;
  dialogueFullscreen: FlowPanelState;
  sequence: FlowPanelState;
  preview: FlowPreviewPanel;
}

const { panels } = defineProps<{
  panels: FlowPanels;
}>();
</script>

<template>
  <div class="contents">
    <div id="flow-versions-panel" class="contents">
      <FlowVersionHistoryPanel
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

    <div id="flow-debug-panel" class="contents">
      <FlowDebugPanel
        :open="panels.debug.open"
        :state="panels.debug.state"
        :nodes="panels.debug.nodes"
        :controls="panels.debug.controls"
      />
    </div>

    <div id="flow-builder-panel" class="contents">
      <FlowBuilderPanel
        :open="panels.builder.open"
        :node-type="panels.builder.nodeType"
        :node-id="panels.builder.nodeId"
        :condition="panels.builder.condition"
        :assignments="panels.builder.assignments"
        :switch-mode="panels.builder.switchMode"
        :project-variables="panels.builder.projectVariables"
        :can-edit="panels.builder.canEdit"
      />
    </div>

    <div id="flow-dialogue-panel" class="contents">
      <FlowDialoguePanel
        :open="panels.dialogue.open"
        :data="panels.dialogue.data"
        :can-edit="panels.dialogue.canEdit"
      />
    </div>

    <div id="flow-dialogue-fullscreen" class="contents">
      <FlowDialogueFullscreenEditor
        :open="panels.dialogueFullscreen.open"
        :data="panels.dialogueFullscreen.data"
        :can-edit="panels.dialogueFullscreen.canEdit"
      />
    </div>

    <div id="flow-sequence-config-panel" class="contents">
      <FlowSequenceConfigPanel
        :open="panels.sequence.open"
        :data="panels.sequence.data"
        :can-edit="panels.sequence.canEdit"
      />
    </div>

    <div id="flow-preview" class="contents">
      <FlowPreview
        :open="panels.preview.open"
        :current-node="panels.preview.currentNode"
        :responses="panels.preview.responses"
        :has-next="panels.preview.hasNext"
        :has-history="panels.preview.hasHistory"
      />
    </div>
  </div>
</template>
