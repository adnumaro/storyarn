<script setup lang="ts">
import { ref } from "vue";
import { useLive } from "@composables/useLive";
import DockActionsPanel from "./dock-panels/DockActionsPanel.vue";
import DockAnnotationButton from "./dock-panels/DockAnnotationButton.vue";
import DockLogicPanel from "./dock-panels/DockLogicPanel.vue";
import DockNarrativePanel from "./dock-panels/DockNarrativePanel.vue";
import DockNavigationPanel from "./dock-panels/DockNavigationPanel.vue";

interface DockPanelExposed {
  close: () => void;
}

const {
  canEdit = false,
  compact = false,
  debugPanelOpen = false,
  workspaceSlug,
  projectSlug,
  flowId,
} = defineProps<{
  canEdit: boolean;
  compact: boolean;
  debugPanelOpen: boolean;
  workspaceSlug: string;
  projectSlug: string;
  flowId: string | number;
}>();

const live = useLive();

const narrativeRef = ref<DockPanelExposed | null>(null);
const logicRef = ref<DockPanelExposed | null>(null);
const navigationRef = ref<DockPanelExposed | null>(null);

function addNode(type: string): void {
  live.pushEvent("add_node", { type });
  narrativeRef.value?.close();
  logicRef.value?.close();
  navigationRef.value?.close();
}

function addAnnotation() {
  live.pushEvent("add_annotation", {});
}

function openVersions() {
  live.pushEvent("open_versions_panel", {});
}

function toggleDebug() {
  live.pushEvent(debugPanelOpen ? "debug_stop" : "debug_start", {});
}

const playUrl = `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${flowId}/play`;
</script>

<template>
  <div v-if="canEdit">
    <div
      class="absolute bottom-3 left-1/2 -translate-x-1/2 z-30 flex items-center gap-1 v2-surface-panel px-2 py-2"
    >
      <!-- Annotation -->
      <DockAnnotationButton @add="addAnnotation" />

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Narrative dropdown -->
      <DockNarrativePanel ref="narrativeRef" @add-node="addNode" />

      <!-- Logic dropdown -->
      <DockLogicPanel ref="logicRef" @add-node="addNode" />

      <!-- Navigation dropdown -->
      <DockNavigationPanel ref="navigationRef" @add-node="addNode" />

      <!-- Actions group (not in compact mode) -->
      <template v-if="!compact">
        <DockActionsPanel
          :debug-panel-open="debugPanelOpen"
          :play-url="playUrl"
          @open-versions="openVersions"
          @toggle-debug="toggleDebug"
        />
      </template>
    </div>
  </div>
</template>
