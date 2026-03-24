<script setup>
import { X } from "lucide-vue-next";
import { computed } from "vue";
import Sidebar from "@/vue/components/layout/Sidebar.vue";
import { useLive } from "@/vue/composables/useLive";
import ConnectionProperties from "./properties/ConnectionProperties.vue";
import PinProperties from "./properties/PinProperties.vue";

const TITLES = {
	zone: "Zone Properties",
	pin: "Pin Properties",
	connection: "Connection Properties",
	annotation: "Annotation Properties",
};

const props = defineProps({
	selectedType: { type: String, default: null },
	selectedElement: { type: Object, default: null },
	canEdit: { type: Boolean, default: false },
	elementPanelOpen: { type: Boolean, default: false },
	projectSheets: { type: Array, default: () => [] },
	projectFlows: { type: Array, default: () => [] },
	projectVariables: { type: Array, default: () => [] },
});

const live = useLive();

const isOpen = computed(
	() => props.elementPanelOpen && props.selectedElement != null,
);

function close() {
	live.pushEvent("close_element_panel", {});
}
</script>

<template>
  <Sidebar side="right" :open="isOpen" @close="close">
    <template #header>
      <div class="flex items-center gap-2 px-3 py-2.5">
        <span class="font-medium text-sm flex-1">{{ TITLES[selectedType] || 'Properties' }}</span>
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

    <div v-if="selectedElement" class="px-3 py-2">
      <PinProperties
        v-if="selectedType === 'pin'"
        :element="selectedElement"
        :can-edit="canEdit"
        :project-sheets="projectSheets"
        :project-flows="projectFlows"
        :project-variables="projectVariables"
      />

      <ConnectionProperties
        v-else-if="selectedType === 'connection'"
        :element="selectedElement"
        :can-edit="canEdit"
      />

      <!-- ZoneProperties will be added in phase 4J -->
    </div>
  </Sidebar>
</template>
