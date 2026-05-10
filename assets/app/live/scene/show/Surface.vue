<script setup lang="ts">
import SceneCanvas from "@modules/scenes/editor/components/canvas/SceneCanvas.vue";
import SceneDock from "@modules/scenes/editor/components/chrome/dock/SceneDock.vue";
import LayerListPopover from "@modules/scenes/editor/components/chrome/layers/LayerListPopover.vue";
import Legend from "@modules/scenes/editor/components/chrome/layers/Legend.vue";

interface SceneSurfaceCanvas {
  key: string;
  id: string;
  mountId: string;
  sceneData: unknown;
  pins: unknown[];
  zones: unknown[];
  connections: unknown[];
  annotations: unknown[];
  layers: unknown[];
  activeTool: string;
  editMode: boolean;
  canEdit: boolean;
  collaboration: {
    userId: number | string;
    locks: Record<string, unknown>;
  };
}

interface SceneSurfaceDock {
  activeTool: string;
  editMode: boolean;
  compact: boolean;
  pendingSheet: unknown;
  projectSheets: unknown[];
  workspaceSlug: string;
  projectSlug: string;
  sceneId: number | string;
}

interface SceneSurfaceLayers {
  layers: unknown[];
  activeLayerId: number | string | null;
  canEdit: boolean;
  editMode: boolean;
  popoverOpen: boolean;
}

interface SceneSurfaceLegend {
  legendData: unknown;
  legendOpen: boolean;
}

interface SceneSurface {
  canvas: SceneSurfaceCanvas;
  dock: SceneSurfaceDock;
  layers: SceneSurfaceLayers;
  legend: SceneSurfaceLegend;
}

const { surface } = defineProps<{
  surface: SceneSurface;
}>();
</script>

<template>
  <div class="h-full relative">
    <div class="absolute inset-0 overflow-hidden">
      <div :id="surface.canvas.mountId" :key="surface.canvas.key" class="w-full h-full">
        <SceneCanvas
          :id="surface.canvas.id"
          class="w-full h-full"
          :scene-data="surface.canvas.sceneData"
          :pins="surface.canvas.pins"
          :zones="surface.canvas.zones"
          :connections="surface.canvas.connections"
          :annotations="surface.canvas.annotations"
          :layers="surface.canvas.layers"
          :active-tool="surface.canvas.activeTool"
          :edit-mode="surface.canvas.editMode"
          :can-edit="surface.canvas.canEdit"
          :collaboration="surface.canvas.collaboration"
        />
      </div>
    </div>

    <div v-if="surface.dock.editMode" id="scene-dock" class="contents">
      <SceneDock
        :active-tool="surface.dock.activeTool"
        :edit-mode="surface.dock.editMode"
        :compact="surface.dock.compact"
        :pending-sheet="surface.dock.pendingSheet"
        :project-sheets="surface.dock.projectSheets"
        :workspace-slug="surface.dock.workspaceSlug"
        :project-slug="surface.dock.projectSlug"
        :scene-id="surface.dock.sceneId"
      />
    </div>

    <div class="absolute bottom-3 right-3 z-20 flex items-end gap-2">
      <div id="scene-layers-popover" class="contents">
        <LayerListPopover
          :layers="surface.layers.layers"
          :active-layer-id="surface.layers.activeLayerId"
          :can-edit="surface.layers.canEdit"
          :edit-mode="surface.layers.editMode"
          :popover-open="surface.layers.popoverOpen"
        />
      </div>

      <div id="scene-legend" class="contents">
        <Legend :legend-data="surface.legend.legendData" :legend-open="surface.legend.legendOpen" />
      </div>
    </div>
  </div>
</template>
