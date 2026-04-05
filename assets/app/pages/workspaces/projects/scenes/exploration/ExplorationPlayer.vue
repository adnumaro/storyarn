<script setup>
import { toRef } from "vue";
import { useLive } from "@composables/useLive";
import CollectionModal from "./CollectionModal.vue";
import { useExplorationKeyboard } from "./composables/useExplorationKeyboard";
import ExplorationCanvas from "./ExplorationCanvas.vue";
import ExplorationToolbar from "./ExplorationToolbar.vue";
import FlowOverlay from "./FlowOverlay.vue";
import SessionPromptModal from "./SessionPromptModal.vue";

const { sceneData, explorationData, sceneName, showZones, flowState, collection, session } =
  defineProps({
    sceneData: { type: Object, required: true },
    explorationData: { type: Object, required: true },
    sceneName: { type: String, default: "" },
    showZones: { type: Boolean, default: false },
    flowState: {
      type: Object,
      default: () => ({ active: false, slide: null, flowName: null, showContinue: false }),
    },
    collection: { type: Object, default: () => ({ open: false, zone: null, items: [] }) },
    session: { type: Object, default: () => ({ promptOpen: false, pending: null }) },
  });

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
