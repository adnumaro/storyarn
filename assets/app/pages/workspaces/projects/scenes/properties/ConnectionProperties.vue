<script setup>
import { Undo2 } from "lucide-vue-next";
import { computed } from "vue";
import { useLive } from "@composables/useLive";

const { element, canEdit } = defineProps({
  element: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
});

const live = useLive();

const waypointCount = computed(() => element?.waypoints?.length || 0);

function straightenPath() {
  live.pushEvent("clear_connection_waypoints", {
    id: String(element.id),
  });
}
</script>

<template>
  <div class="space-y-3">
    <button
      v-if="canEdit && waypointCount > 0"
      type="button"
      class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-md hover:bg-accent transition-colors"
      @click="straightenPath"
    >
      <Undo2 class="size-3.5" />
      Straighten path
    </button>
    <p v-else class="text-sm text-muted-foreground italic">No waypoints</p>
  </div>
</template>
