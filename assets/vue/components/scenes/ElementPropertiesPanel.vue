<script setup>
import { Undo2, X } from "lucide-vue-next";
import { computed } from "vue";
import Sidebar from "@/vue/components/layout/Sidebar.vue";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	selectedType: { type: String, default: null },
	selectedElement: { type: Object, default: null },
	canEdit: { type: Boolean, default: false },
	elementPanelOpen: { type: Boolean, default: false },
});

const live = useLive();

const isOpen = computed(
	() => props.elementPanelOpen && props.selectedElement != null,
);

const panelTitle = computed(() => {
	const titles = {
		zone: "Zone Properties",
		pin: "Pin Properties",
		connection: "Connection Properties",
		annotation: "Annotation Properties",
	};
	return titles[props.selectedType] || "Properties";
});

function close() {
	live.pushEvent("close_element_panel", {});
}

// Connection-specific
const waypointCount = computed(() => {
	if (props.selectedType !== "connection") return 0;
	return props.selectedElement?.waypoints?.length || 0;
});

function straightenPath() {
	if (!props.selectedElement) return;
	live.pushEvent("clear_connection_waypoints", {
		id: String(props.selectedElement.id),
	});
}
</script>

<template>
  <Sidebar side="right" :open="isOpen" @close="close">
    <template #header>
      <div class="flex items-center gap-2 px-3 py-2.5">
        <span class="font-medium text-sm flex-1">{{ panelTitle }}</span>
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

    <div v-if="selectedElement" class="px-3 py-2 space-y-3">
      <!-- Connection properties -->
      <template v-if="selectedType === 'connection'">
        <button
          v-if="canEdit && waypointCount > 0"
          type="button"
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-md hover:bg-accent transition-colors"
          @click="straightenPath"
        >
          <Undo2 class="size-3.5" />
          Straighten path
        </button>
        <p v-else class="text-sm text-muted-foreground italic">
          No waypoints
        </p>
      </template>

      <!-- Future: pin, zone properties (4I, 4J) -->
    </div>
  </Sidebar>
</template>
