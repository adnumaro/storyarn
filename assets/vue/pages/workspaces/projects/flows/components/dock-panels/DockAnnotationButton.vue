<script setup>
import { StickyNote } from "lucide-vue-next";

defineEmits(["add"]);
</script>

<template>
  <div class="v2-dock-item group relative">
    <button type="button" class="v2-dock-btn" @click="$emit('add')">
      <StickyNote class="size-5" />
    </button>
    <div class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">Note</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        Add a sticky note to the canvas
      </div>
    </div>
  </div>
</template>
