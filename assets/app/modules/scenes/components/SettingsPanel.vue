<script setup lang="ts">
import { Settings, X } from "lucide-vue-next";
import { computed } from "vue";
import Sidebar from "@components/layout/Sidebar.vue";
import { useLive } from "@composables/useLive";
import AmbientFlowsSection from "../settings/AmbientFlowsSection.vue";
import BackgroundSection from "../settings/BackgroundSection.vue";
import DimensionsSection from "../settings/DimensionsSection.vue";
import DisplayModeSection from "../settings/DisplayModeSection.vue";
import ScaleSection from "../settings/ScaleSection.vue";

interface SceneSettings {
  backgroundUrl: string | null;
  explorationDisplayMode: string;
  defaultZoom: number;
  scaleValue: number;
  scaleUnit: string;
  width: number;
  height: number;
}

interface AmbientFlow {
  id: number | string;
  flowId: number;
  flowName: string;
  enabled: boolean;
  triggerType: string;
  triggerConfig?: { interval_ms?: number; variable_ref?: string };
  priority: number;
}

interface ProjectFlow {
  id: number;
  name: string;
  shortcut?: string;
}

const {
  scene = null,
  canEdit = false,
  ambientFlows = [],
  projectFlows = [],
  sceneSettingsOpen = false,
} = defineProps<{
  scene: SceneSettings | null;
  canEdit: boolean;
  ambientFlows: AmbientFlow[];
  projectFlows: ProjectFlow[];
  sceneSettingsOpen: boolean;
}>();

const live = useLive();
const isOpen = computed(() => sceneSettingsOpen && scene != null);

function close(): void {
  live.pushEvent("close_scene_settings", {});
}
</script>

<template>
  <Sidebar side="right" :open="isOpen" @close="close">
    <template #header>
      <div class="flex items-center gap-2 px-3 py-2.5">
        <Settings class="size-3.5 text-muted-foreground" />
        <span class="font-medium text-sm flex-1">Scene Settings</span>
        <button
          type="button"
          class="inline-flex items-center justify-center size-6 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
          title="Close panel"
          @click="close"
        >
          <X class="size-3" />
        </button>
      </div>
    </template>

    <div v-if="scene" class="space-y-4">
      <BackgroundSection :background-url="scene.backgroundUrl" :can-edit="canEdit" />
      <DisplayModeSection
        :display-mode="scene.explorationDisplayMode"
        :default-zoom="scene.defaultZoom"
        :can-edit="canEdit"
      />
      <ScaleSection :scale-value="scene.scaleValue" :scale-unit="scene.scaleUnit" />
      <DimensionsSection :width="scene.width" :height="scene.height" />
      <AmbientFlowsSection
        :ambient-flows="ambientFlows"
        :project-flows="projectFlows"
        :can-edit="canEdit"
      />
    </div>
  </Sidebar>
</template>
