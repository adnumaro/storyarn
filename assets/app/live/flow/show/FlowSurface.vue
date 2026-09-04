<script setup lang="ts">
import { useLiveVue } from "live_vue";
import { computed } from "vue";
import FlowDock from "@modules/flows/editor/components/chrome/dock/FlowDock.vue";
import FlowCollabToast from "@modules/flows/editor/components/collab/CollabToast.vue";
import FlowCanvas from "./FlowCanvas.vue";

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
  commentCounts?: Record<string, number>;
  commentFocusNodeId?: number | null;
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

interface FlowCanvasComments {
  enabled: boolean;
  counts: Record<string, number>;
  focusNodeId: number | null;
}

const { surface: initialSurface } = defineProps<{
  surface: FlowSurface;
}>();

const live = useLiveVue();
// `v-inject` keeps this boundary alive while route diffs replace the surface payload.
const surface = computed(
  () => (live.vue?.props?.surface as FlowSurface | undefined) ?? initialSurface,
);
const emptyCommentCounts: Record<string, number> = {};
const comments = computed<FlowCanvasComments>((previous) => {
  const counts = surface.value.canvas.commentCounts ?? emptyCommentCounts;
  const focusNodeId = surface.value.canvas.commentFocusNodeId ?? null;
  if (previous && previous.counts === counts && previous.focusNodeId === focusNodeId) {
    return previous;
  }
  return { enabled: true, counts, focusNodeId };
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
