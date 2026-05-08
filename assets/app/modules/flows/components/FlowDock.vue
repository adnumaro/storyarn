<script setup lang="ts">
import { Hand, MousePointer2 } from "lucide-vue-next";
import { ref } from "vue";
import { useLive } from "../../../shared/composables/useLive";
import { activeFlowTool, type FlowTool } from "../lib/flow-tool-state";
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

function setTool(tool: FlowTool): void {
  activeFlowTool.value = tool;
}

const playUrl = `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${flowId}/play`;
</script>

<template>
  <div v-if="canEdit">
    <div
      class="absolute bottom-3 left-1/2 -translate-x-1/2 z-30 flex items-center gap-1 surface-panel px-2 py-2 h-10"
    >
      <!-- Tool mode: select / pan. Client-only state via shared ref. -->
      <div class="dock-item group relative">
        <button
          type="button"
          class="dock-btn"
          :class="{ 'dock-btn-active': activeFlowTool === 'select' }"
          @click="setTool('select')"
        >
          <MousePointer2 class="size-5" />
        </button>
        <div class="dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">{{ $t("flows.dock.select") }}</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            {{ $t("flows.dock.select_desc") }}
          </div>
        </div>
      </div>

      <div class="dock-item group relative">
        <button
          type="button"
          class="dock-btn"
          :class="{ 'dock-btn-active': activeFlowTool === 'pan' }"
          @click="setTool('pan')"
        >
          <Hand class="size-5" />
        </button>
        <div class="dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">{{ $t("flows.dock.pan") }}</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            {{ $t("flows.dock.pan_desc") }}
          </div>
        </div>
      </div>

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

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
