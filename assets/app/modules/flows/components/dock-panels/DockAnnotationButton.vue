<script setup lang="ts">
import { StickyNote } from "lucide-vue-next";

defineEmits<{
  add: [];
}>();
</script>

<template>
  <div class="dock-item group relative">
    <button type="button" class="dock-btn" @click="$emit('add')">
      <StickyNote class="size-5" />
    </button>
    <div class="dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">{{ $t("flows.dock.add_note") }}</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        {{ $t("flows.dock.add_note") }}
      </div>
    </div>
  </div>
</template>
