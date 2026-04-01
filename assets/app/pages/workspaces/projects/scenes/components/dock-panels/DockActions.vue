<script setup>
import { History, Play } from "lucide-vue-next";
import DockToolButton from "./DockToolButton.vue";

const { playUrl } = defineProps({
  playUrl: { type: String, required: true },
});

const emit = defineEmits(["open-versions"]);
</script>

<template>
  <!-- Separator -->
  <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

  <!-- Version History -->
  <DockToolButton
    :icon="History"
    tooltip-title="Version History"
    tooltip-description="View and manage version history"
    @click="emit('open-versions')"
  />

  <!-- Play -->
  <DockToolButton
    :icon="Play"
    tag="a"
    :href="playUrl"
    tooltip-title="Play"
    tooltip-description="Play exploration mode"
  />
</template>
