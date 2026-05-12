<script setup lang="ts">
import { computed } from "vue";
import { useLiveVue } from "live_vue";
import { ImagePlus, Upload } from "lucide-vue-next";
import SceneCanvas from "@modules/scenes/editor/components/canvas/SceneCanvas.vue";
import SceneDock from "@modules/scenes/editor/components/chrome/dock/SceneDock.vue";
import LayerListPopover from "@modules/scenes/editor/components/chrome/layers/LayerListPopover.vue";
import Legend from "@modules/scenes/editor/components/chrome/layers/Legend.vue";
import SceneCollabToast from "@modules/scenes/editor/components/collab/CollabToast.vue";

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

interface SceneSurfaceUploadEntry {
  ref: string;
  name: string;
  baseName: string;
  extension: string;
  progress: number;
}

interface SceneSurfaceUpload {
  canUpload: boolean;
  backgroundSet: boolean;
  inputRef: string | null;
  dropTarget: string | null;
  entries: SceneSurfaceUploadEntry[];
}

interface SceneSurface {
  canvas: SceneSurfaceCanvas;
  dock: SceneSurfaceDock;
  layers: SceneSurfaceLayers;
  legend: SceneSurfaceLegend;
  upload: SceneSurfaceUpload;
}

const { surface: initialSurface } = defineProps<{
  surface: SceneSurface;
}>();

const live = useLiveVue();
const surface = computed(
  () => (live.vue.props.surface as SceneSurface | undefined) ?? initialSurface,
);
</script>

<template>
  <div class="h-full relative">
    <div
      id="scene-canvas-wrapper"
      class="absolute inset-0 overflow-hidden"
      :phx-drop-target="surface.upload.dropTarget || undefined"
    >
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

      <div
        v-if="surface.upload.canUpload && !surface.upload.backgroundSet"
        class="absolute inset-0 flex items-center justify-center z-10 pointer-events-none"
      >
        <label
          :for="surface.upload.inputRef || undefined"
          class="pointer-events-auto cursor-pointer group flex flex-col items-center gap-3 p-8 rounded-xl border-2 border-dashed border-foreground/15 hover:border-primary/40 hover:bg-background/50 transition-colors"
        >
          <ImagePlus class="size-10 opacity-20 group-hover:opacity-50 transition-opacity" />
          <span class="text-sm text-foreground/40 group-hover:text-foreground/60 transition-colors">
            {{ $t("scenes.settings.bg_upload") }}
          </span>
          <span class="text-xs text-foreground/25">
            {{ $t("scenes.settings.bg_drag_drop") }}
          </span>
        </label>
      </div>

      <div
        v-if="surface.upload.canUpload"
        id="canvas-drop-indicator"
        class="hidden absolute inset-0 z-10 bg-primary/5 border-2 border-dashed border-primary/30 flex items-center justify-center pointer-events-none"
      >
        <div class="text-center">
          <ImagePlus class="size-12 text-primary/50 mx-auto mb-2" />
          <p class="text-sm font-medium text-primary/60">
            {{ $t("scenes.settings.bg_drop_to_set") }}
          </p>
        </div>
      </div>
    </div>

    <div
      v-for="entry in surface.upload.entries"
      :key="entry.ref"
      class="absolute bottom-20 left-1/2 -translate-x-1/2 z-20 bg-background rounded-lg border border-border shadow-lg px-4 py-2 flex items-center gap-3"
    >
      <Upload class="size-4 animate-pulse text-primary" />
      <div class="w-40">
        <div class="text-xs text-muted-foreground mb-1 flex min-w-0">
          <span class="truncate">{{ entry.baseName }}</span>
          <span class="flex-shrink-0">{{ entry.extension }}</span>
        </div>
        <div class="w-full bg-muted rounded-full h-1.5">
          <div
            class="bg-primary h-1.5 rounded-full transition-all"
            :style="{ width: `${entry.progress}%` }"
          />
        </div>
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

    <div id="scene-collab-toast" class="contents">
      <SceneCollabToast />
    </div>
  </div>
</template>
