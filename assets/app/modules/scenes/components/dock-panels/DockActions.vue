<script setup lang="ts">
import { History, Play } from "lucide-vue-next";
import DockToolButton from "./DockToolButton.vue";

const { playUrl } = defineProps<{
  playUrl: string;
}>();

const emit = defineEmits<{
  "open-versions": [];
}>();
</script>

<template>
  <!-- Separator -->
  <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

  <!-- Version History -->
  <DockToolButton
    :icon="History"
    :tooltip-title="$t('scenes.dock.version_history')"
    :tooltip-description="$t('scenes.dock.version_history_desc')"
    @click="emit('open-versions')"
  />

  <!-- Play -->
  <DockToolButton
    :icon="Play"
    tag="a"
    :href="playUrl"
    :tooltip-title="$t('scenes.dock.play')"
    :tooltip-description="$t('scenes.dock.play_desc')"
  />
</template>
