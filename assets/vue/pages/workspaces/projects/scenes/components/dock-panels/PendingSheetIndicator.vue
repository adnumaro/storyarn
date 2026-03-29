<script setup>
import { MapPin, X } from "lucide-vue-next";

defineProps({
  pendingSheet: { type: Object, required: true },
});

const emit = defineEmits(["cancel"]);
</script>

<template>
  <div
    class="absolute bottom-24 left-1/2 -translate-x-1/2 z-30 bg-primary/10 border border-primary/30 rounded-lg px-3 py-1.5 text-xs flex items-center gap-2"
  >
    <MapPin class="size-3.5" />
    <span>
      Click on canvas to place <strong>{{ pendingSheet.name }}</strong>
    </span>
    <button
      type="button"
      class="v2-dock-btn !size-5 !rounded-md"
      @click="emit('cancel')"
    >
      <X class="size-3" />
    </button>
  </div>
</template>
