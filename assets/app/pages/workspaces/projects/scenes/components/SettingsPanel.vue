<script setup>
import { Settings, X } from "lucide-vue-next";
import { computed } from "vue";
import Sidebar from "@components/layout/Sidebar.vue";
import { useLive } from "@composables/useLive";
import AmbientFlowsSection from "../settings/AmbientFlowsSection.vue";
import BackgroundSection from "../settings/BackgroundSection.vue";
import DimensionsSection from "../settings/DimensionsSection.vue";
import DisplayModeSection from "../settings/DisplayModeSection.vue";
import ScaleSection from "../settings/ScaleSection.vue";

const props = defineProps({
  scene: { type: Object, default: null },
  canEdit: { type: Boolean, default: false },
  ambientFlows: { type: Array, default: () => [] },
  projectFlows: { type: Array, default: () => [] },
  sceneSettingsOpen: { type: Boolean, default: false },
});

const live = useLive();
const isOpen = computed(() => props.sceneSettingsOpen && props.scene != null);

function close() {
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
