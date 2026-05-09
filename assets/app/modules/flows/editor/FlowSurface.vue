<script setup lang="ts">
import FlowDock from "./components/chrome/dock/FlowDock.vue";
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

const { surface } = defineProps<{
  surface: FlowSurface;
}>();
</script>

<template>
  <div class="h-full relative">
    <div :key="surface.canvas.key" class="w-full h-full">
      <FlowCanvas
        class="w-full h-full"
        :flow-data="surface.canvas.flowData"
        :variable-map="surface.canvas.variableMap"
        :loading="surface.canvas.loading"
        :readonly="surface.canvas.readonly"
        :user-id="surface.canvas.userId"
        :user-color="surface.canvas.userColor"
        :canvas-id="surface.canvas.canvasId"
        :toolbar-data="surface.canvas.toolbarData"
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
  </div>
</template>
