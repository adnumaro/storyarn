<script setup lang="ts">
import { toRef } from "vue";
import { useLive } from "@shared/composables/useLive.ts";
import CollectionModal from "@modules/scenes/exploration/components/CollectionModal.vue";
import {
  useExplorationKeyboard,
  type FlowSlide,
} from "@modules/scenes/exploration/composables/useExplorationKeyboard";
import ExplorationCanvas from "@modules/scenes/exploration/components/ExplorationCanvas.vue";
import ExplorationToolbar from "@modules/scenes/exploration/components/ExplorationToolbar.vue";
import FlowOverlay from "@modules/scenes/exploration/components/FlowOverlay.vue";
import SessionPromptModal from "@modules/scenes/exploration/components/SessionPromptModal.vue";

interface FlowState {
  active: boolean;
  slide: FlowSlide | null;
  flowName: string | null;
  showContinue: boolean;
}

interface CollectionState {
  open: boolean;
  zone: { emptyMessage?: string; collectAllEnabled?: boolean } | null;
  items: { id: number | string; label?: string; _sheet_name?: string }[];
}

interface SessionState {
  promptOpen: boolean;
  pending: { sceneName?: string; updatedAt?: string } | null;
}

const {
  sceneData,
  explorationData,
  sceneName = "",
  showZones = false,
  flowState = { active: false, slide: null, flowName: null, showContinue: false },
  collection = { open: false, zone: null, items: [] },
  session = { promptOpen: false, pending: null },
} = defineProps<{
  sceneData: { width?: number; height?: number; backgroundUrl?: string };
  explorationData: InstanceType<typeof ExplorationCanvas>["$props"]["explorationData"];
  sceneName?: string;
  showZones?: boolean;
  flowState?: FlowState;
  collection?: CollectionState;
  session?: SessionState;
}>();

const live = useLive();

useExplorationKeyboard({
  flowMode: toRef(() => flowState.active),
  activeFlowSlide: toRef(() => flowState.slide),
  pushEvent: live.pushEvent,
});
</script>

<template>
  <div class="w-full h-full bg-background flex flex-col">
    <ExplorationToolbar
      :scene-name="sceneName"
      :active-flow-name="flowState.flowName"
      :flow-mode="flowState.active"
      :show-zones="showZones"
    />

    <div class="flex-1 relative overflow-hidden">
      <!-- Canvas -->
      <div class="w-full h-full">
        <ExplorationCanvas
          :scene-data="sceneData"
          :exploration-data="explorationData"
          :show-zones="showZones"
          :flow-mode="flowState.active"
        />
      </div>

      <!-- Flow overlay -->
      <FlowOverlay
        v-if="flowState.active && flowState.slide"
        :slide="flowState.slide"
        :flow-name="flowState.flowName"
        :show-continue="flowState.showContinue"
      />
    </div>

    <!-- Collection modal -->
    <CollectionModal :open="collection.open" :zone="collection.zone" :items="collection.items" />

    <!-- Session prompt -->
    <SessionPromptModal :open="session.promptOpen" :pending-session="session.pending" />
  </div>
</template>
