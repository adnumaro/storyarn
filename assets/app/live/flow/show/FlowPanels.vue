<script setup lang="ts">
import { computed } from "vue";
import FlowBuilderPanel from "@modules/flows/editor/components/panels/FlowBuilderPanel.vue";
import FlowCommentsPanel from "@modules/flows/editor/components/panels/FlowCommentsPanel.vue";
import type { FlowCommentsPanelState } from "@modules/flows/types/comments";
import FlowDebugPanel from "@modules/flows/editor/components/panels/FlowDebugPanel.vue";
import FlowDialogueFullscreenEditor from "@modules/flows/editor/components/panels/FlowDialogueFullscreenEditor.vue";
import FlowDialoguePanel from "@modules/flows/editor/components/panels/FlowDialoguePanel.vue";
import FlowPreview from "@modules/flows/editor/components/panels/FlowPreview.vue";
import FlowSequenceConfigPanel from "@modules/flows/editor/components/panels/FlowSequenceConfigPanel.vue";
import FlowVersionHistoryPanel from "@modules/flows/editor/components/panels/FlowVersionHistoryPanel.vue";

type ServerPayload = any;

interface FlowVersionsPanel {
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

interface FlowDebugPanelState {
  open: boolean;
  state: ServerPayload;
  nodes: Record<string, ServerPayload>;
  controls: ServerPayload;
}

interface FlowBuilderPanelState {
  open: boolean;
  nodeType: string | null;
  nodeId: number | string | null;
  condition: ServerPayload;
  assignments: ServerPayload[] | null;
  switchMode: boolean | null;
  projectVariables: string;
  canEdit: boolean;
}

interface FlowPanelState {
  open: boolean;
  data: ServerPayload;
  canEdit: boolean;
}

interface FlowPreviewPanel {
  open: boolean;
  currentNode: ServerPayload;
  responses: ServerPayload[];
  hasNext: boolean;
  hasHistory: boolean;
}

interface FlowPanels {
  comments?: FlowCommentsPanelState;
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

const commentsPanelOpen = computed(
  () => panels.comments?.open && panels.comments.presentation !== "canvas",
);
</script>

<template>
  <div class="contents">
    <div v-if="panels.comments" id="flow-comments-panel" class="contents">
      <FlowCommentsPanel :state="panels.comments" />
    </div>
    <div id="flow-versions-panel" class="contents">
      <FlowVersionHistoryPanel
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

    <div id="flow-debug-panel" class="contents">
      <FlowDebugPanel
        :open="panels.debug.open && !commentsPanelOpen"
        :state="panels.debug.state"
        :nodes="panels.debug.nodes"
        :controls="panels.debug.controls"
      />
    </div>

    <div id="flow-builder-panel" class="contents">
      <FlowBuilderPanel
        :open="panels.builder.open && !commentsPanelOpen"
        :node-type="panels.builder.nodeType"
        :node-id="panels.builder.nodeId"
        :condition="panels.builder.condition"
        :assignments="panels.builder.assignments ?? undefined"
        :switch-mode="panels.builder.switchMode ?? undefined"
        :project-variables="panels.builder.projectVariables"
        :can-edit="panels.builder.canEdit"
      />
    </div>

    <div id="flow-dialogue-panel" class="contents">
      <FlowDialoguePanel
        :open="panels.dialogue.open && !commentsPanelOpen"
        :data="panels.dialogue.data"
        :can-edit="panels.dialogue.canEdit"
      />
    </div>

    <div id="flow-dialogue-fullscreen" class="contents">
      <FlowDialogueFullscreenEditor
        :open="panels.dialogueFullscreen.open && !commentsPanelOpen"
        :data="panels.dialogueFullscreen.data"
        :can-edit="panels.dialogueFullscreen.canEdit"
      />
    </div>

    <div id="flow-sequence-config-panel" class="contents">
      <FlowSequenceConfigPanel
        :open="panels.sequence.open && !commentsPanelOpen"
        :data="panels.sequence.data"
        :can-edit="panels.sequence.canEdit"
      />
    </div>

    <div id="flow-preview" class="contents">
      <FlowPreview
        :open="panels.preview.open && !commentsPanelOpen"
        :current-node="panels.preview.currentNode"
        :responses="panels.preview.responses"
        :has-next="panels.preview.hasNext"
        :has-history="panels.preview.hasHistory"
      />
    </div>
  </div>
</template>
