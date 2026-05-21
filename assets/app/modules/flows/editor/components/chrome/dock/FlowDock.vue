<script setup lang="ts">
import { Hand, MousePointer2 } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useLive } from "../../../../../../shared/composables/useLive";
import { activeFlowPlacement, startFlowPlacement } from "../../../lib/flow-placement-state";
import { activeFlowTool, type FlowTool } from "../../../lib/flow-tool-state";
import type { FlowNodeType } from "../../../lib/node-configs";
import DockActionsPanel from "./DockActionsPanel.vue";
import DockAnnotationButton from "./DockAnnotationButton.vue";
import DockLogicPanel from "./DockLogicPanel.vue";
import DockNarrativePanel from "./DockNarrativePanel.vue";
import DockNavigationPanel from "./DockNavigationPanel.vue";

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
  startFlowPlacement({ kind: "node", type: type as FlowNodeType });
  narrativeRef.value?.close();
  logicRef.value?.close();
  navigationRef.value?.close();
}

function addAnnotation() {
  startFlowPlacement({ kind: "annotation" });
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

const activePlacementType = computed(() =>
  activeFlowPlacement.value?.kind === "node" ? activeFlowPlacement.value.type : null,
);

const annotationPlacementActive = computed(() => activeFlowPlacement.value?.kind === "annotation");

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
      <DockAnnotationButton :active="annotationPlacementActive" @add="addAnnotation" />

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Narrative dropdown -->
      <DockNarrativePanel
        ref="narrativeRef"
        :active-type="activePlacementType"
        @add-node="addNode"
      />

      <!-- Logic dropdown -->
      <DockLogicPanel ref="logicRef" :active-type="activePlacementType" @add-node="addNode" />

      <!-- Navigation dropdown -->
      <DockNavigationPanel
        ref="navigationRef"
        :active-type="activePlacementType"
        @add-node="addNode"
      />

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
