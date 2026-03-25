<script setup>
import { toRef } from "vue";
import CollectionModal from "./CollectionModal.vue";
import { useExplorationKeyboard } from "./composables/useExplorationKeyboard";
import ExplorationCanvas from "./ExplorationCanvas.vue";
import ExplorationToolbar from "./ExplorationToolbar.vue";
import FlowOverlay from "./FlowOverlay.vue";
import SessionPromptModal from "./SessionPromptModal.vue";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	sceneData: { type: Object, required: true },
	explorationData: { type: Object, required: true },
	sceneName: { type: String, default: "" },
	showZones: { type: Boolean, default: false },
	flowMode: { type: Boolean, default: false },
	sessionPrompt: { type: Boolean, default: false },
	pendingSession: { type: Object, default: null },
	collectionMode: { type: Boolean, default: false },
	collectionZone: { type: Object, default: null },
	collectionItems: { type: Array, default: () => [] },
	activeFlowSlide: { type: Object, default: null },
	activeFlowName: { type: String, default: null },
	showFlowContinue: { type: Boolean, default: false },
});

const live = useLive();

useExplorationKeyboard({
	flowMode: toRef(props, "flowMode"),
	activeFlowSlide: toRef(props, "activeFlowSlide"),
	pushEvent: live.pushEvent,
});
</script>

<template>
  <div class="w-full h-full bg-background flex flex-col">
    <ExplorationToolbar
      :scene-name="sceneName"
      :active-flow-name="activeFlowName"
      :flow-mode="flowMode"
      :show-zones="showZones"
    />

    <div class="flex-1 relative overflow-hidden">
      <!-- Canvas -->
      <div class="w-full h-full">
        <ExplorationCanvas
          :scene-data="sceneData"
          :exploration-data="explorationData"
          :show-zones="showZones"
          :flow-mode="flowMode"
        />
      </div>

      <!-- Flow overlay -->
      <FlowOverlay
        v-if="flowMode && activeFlowSlide"
        :slide="activeFlowSlide"
        :flow-name="activeFlowName"
        :show-continue="showFlowContinue"
      />
    </div>

    <!-- Collection modal -->
    <CollectionModal
      :open="collectionMode"
      :zone="collectionZone"
      :items="collectionItems"
    />

    <!-- Session prompt -->
    <SessionPromptModal
      :open="sessionPrompt"
      :pending-session="pendingSession"
    />
  </div>
</template>
