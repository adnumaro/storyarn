<script setup lang="ts">
import { useLiveVue } from "live_vue";
import { computed } from "vue";
import FlowDock from "@modules/flows/editor/components/chrome/dock/FlowDock.vue";
import FlowCollabToast from "@modules/flows/editor/components/collab/CollabToast.vue";
import FlowCanvas from "./FlowCanvas.vue";
import type { FlowCommentsPanelState, FlowCommentThread } from "@modules/flows/types/comments";

interface FlowSurfaceCanvasData {
  key: string;
  flowData: string | null;
  variableMap: string | null;
  loading: boolean;
  readonly: boolean;
  userId: number | string;
  userColor: string;
  canvasId: string;
  toolbarData: string;
  commentPins?: FlowCommentThread[];
  comments?: FlowCommentsPanelState | null;
  commentFocusThreadId?: number | null;
}

interface FlowDockSurface {
  canEdit: boolean;
  compact: boolean;
  debugPanelOpen: boolean;
  workspaceSlug: string;
  projectSlug: string;
  flowId: number | string;
}

interface FlowSurface {
  canvas: FlowSurfaceCanvasData;
  dock: FlowDockSurface;
}

const { surface: initialSurface } = defineProps<{
  surface: FlowSurface;
}>();

const live = useLiveVue();
// `v-inject` keeps this boundary alive while route diffs replace the surface payload.
const surface = computed(
  () => (live.vue?.props?.surface as FlowSurface | undefined) ?? initialSurface,
);
const comments = computed(() => {
  const canvas = surface.value.canvas;
  if (!canvas.comments) return null;
  return {
    state: canvas.comments,
    pins: canvas.commentPins ?? [],
    focusThreadId: canvas.commentFocusThreadId ?? null,
  };
});
</script>

<template>
  <div class="h-full relative">
    <div :key="surface.canvas.key" class="w-full h-full">
      <FlowCanvas
        :flow-data="surface.canvas.flowData"
        :variable-map="surface.canvas.variableMap"
        :loading="surface.canvas.loading"
        :readonly="surface.canvas.readonly"
        :user-id="surface.canvas.userId"
        :user-color="surface.canvas.userColor"
        :canvas-id="surface.canvas.canvasId"
        :toolbar-data="surface.canvas.toolbarData"
        :comments="comments"
      />
    </div>

    <div id="flow-dock" class="contents">
      <FlowDock
        :can-edit="surface.dock.canEdit"
        :compact="surface.dock.compact"
        :debug-panel-open="surface.dock.debugPanelOpen"
        :workspace-slug="surface.dock.workspaceSlug"
        :project-slug="surface.dock.projectSlug"
        :flow-id="surface.dock.flowId"
      />
    </div>

    <div id="flow-collab-toast" class="contents">
      <FlowCollabToast />
    </div>
  </div>
</template>
