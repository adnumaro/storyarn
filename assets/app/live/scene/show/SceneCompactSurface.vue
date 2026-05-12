<script setup lang="ts">
import SceneCanvas from "@modules/scenes/editor/components/canvas/SceneCanvas.vue";
import SceneDock from "@modules/scenes/editor/components/chrome/dock/SceneDock.vue";

interface EntityLock {
  userId: number | string;
}

interface CollaborationData {
  userId: number | string;
  locks: Record<string, EntityLock>;
}

interface SceneCompactCanvas {
  id: string;
  sceneData: unknown;
  pins: unknown[];
  zones: unknown[];
  connections: unknown[];
  annotations: unknown[];
  layers: unknown[];
  activeTool: string;
  editMode: boolean;
  canEdit: boolean;
  collaboration: CollaborationData;
}

interface SceneCompactDock {
  activeTool: string;
  editMode: boolean;
  compact: boolean;
  pendingSheet: unknown;
  projectSheets: unknown[];
  workspaceSlug: string;
  projectSlug: string;
  sceneId: number | string;
}

interface SceneCompactSurface {
  canvas: SceneCompactCanvas;
  dock: SceneCompactDock;
}

const { surface } = defineProps<{
  surface: SceneCompactSurface;
}>();
</script>

<template>
  <div class="h-full relative">
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

    <SceneDock
      v-if="surface.dock.editMode"
      id="scene-dock-compact"
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
</template>
