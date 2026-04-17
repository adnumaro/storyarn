<script setup lang="ts">
import { Bug, History, Play } from "lucide-vue-next";

const { debugPanelOpen = false, playUrl } = defineProps<{
  debugPanelOpen: boolean;
  playUrl: string;
}>();

const emit = defineEmits<{
  "open-versions": [];
  "toggle-debug": [];
}>();
</script>

<template>
  <!-- Separator -->
  <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

  <!-- Version History -->
  <div class="dock-item group relative">
    <button type="button" class="dock-btn" @click="$emit('open-versions')">
      <History class="size-5" />
    </button>
    <div class="dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">{{ $t("flows.dock.version_history") }}</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        {{ $t("flows.dock.version_history_desc") }}
      </div>
    </div>
  </div>

  <!-- Play -->
  <div class="dock-item group relative">
    <a :href="playUrl" data-phx-link="redirect" data-phx-link-state="push" class="dock-btn">
      <Play class="size-5" />
    </a>
    <div class="dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">{{ $t("flows.dock.play") }}</div>
      <div class="text-xs text-muted-foreground leading-relaxed">{{ $t("flows.dock.play_desc") }}</div>
    </div>
  </div>

  <!-- Debug -->
  <div class="dock-item group relative">
    <button
      type="button"
      class="dock-btn"
      :class="{ 'dock-btn-active': debugPanelOpen }"
      @click="$emit('toggle-debug')"
    >
      <Bug class="size-5" />
    </button>
    <div class="dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">{{ $t("flows.dock.debug") }}</div>
      <div class="text-xs text-muted-foreground leading-relaxed">{{ $t("flows.dock.debug_desc") }}</div>
    </div>
  </div>
</template>
