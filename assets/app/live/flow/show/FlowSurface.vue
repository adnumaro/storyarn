<script setup lang="ts">
import { useLiveVue } from "live_vue";
import { computed } from "vue";
import FlowDock from "@modules/flows/editor/components/chrome/dock/FlowDock.vue";
import FlowCollabToast from "@modules/flows/editor/components/collab/CollabToast.vue";
import FlowDebugPanel from "@modules/flows/editor/components/panels/FlowDebugPanel.vue";
import FlowSequenceStage from "@modules/flows/editor/components/sequence/FlowSequenceStage.vue";
import type { SequenceStageState } from "@modules/flows/sequence/types";
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

type FlowDebugPanelProps = InstanceType<typeof FlowDebugPanel>["$props"];

interface FlowDebugSurface {
  open: FlowDebugPanelProps["open"];
  state: FlowDebugPanelProps["state"];
  nodes: FlowDebugPanelProps["nodes"];
  controls: FlowDebugPanelProps["controls"];
}

interface FlowSurface {
  canvas: FlowSurfaceCanvasData;
  dock: FlowDockSurface;
  stage?: SequenceStageState;
  debug?: FlowDebugSurface;
}

const { surface: initialSurface } = defineProps<{
  surface: FlowSurface;
}>();

const live = useLiveVue();
// `v-inject` keeps this boundary alive while route diffs replace the surface payload.
const surface = computed(
  () => (live.vue?.props?.surface as FlowSurface | undefined) ?? initialSurface,
);
const emptyStage: SequenceStageState = { status: "empty" };
const stage = computed(() => surface.value.stage ?? emptyStage);
const debugOpen = computed(() => Boolean(surface.value.debug?.open && surface.value.debug.state));
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
  <div class="h-full min-h-0 relative flex flex-col bg-background">
    <FlowSequenceStage
      :stage="stage"
      :can-edit="surface.dock.canEdit && !surface.canvas.readonly"
    />

    <div id="flow-lower-workspace" class="relative flex-1 min-h-0 overflow-hidden">
      <div
        :key="surface.canvas.key"
        v-show="!debugOpen"
        class="absolute inset-0"
        data-flow-workspace="canvas"
      >
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
      </div>

      <div
        v-if="surface.debug"
        v-show="debugOpen"
        class="absolute inset-0"
        data-flow-workspace="debug"
      >
        <FlowDebugPanel
          embedded
          :open="surface.debug.open"
          :state="surface.debug.state"
          :nodes="surface.debug.nodes"
          :controls="surface.debug.controls"
        />
      </div>
    </div>

    <div id="flow-collab-toast" class="contents">
      <FlowCollabToast />
    </div>
  </div>
</template>
