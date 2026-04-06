<script setup>
import { Bug, History, Play } from "lucide-vue-next";

const { debugPanelOpen, playUrl } = defineProps({
  debugPanelOpen: { type: Boolean, default: false },
  playUrl: { type: String, required: true },
});

const emit = defineEmits(["open-versions", "toggle-debug"]);
</script>

<template>
  <!-- Separator -->
  <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

  <!-- Version History -->
  <div class="v2-dock-item group relative">
    <button type="button" class="v2-dock-btn" @click="$emit('open-versions')">
      <History class="size-5" />
    </button>
    <div class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">Version History</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        View and manage version history
      </div>
    </div>
  </div>

  <!-- Play -->
  <div class="v2-dock-item group relative">
    <a :href="playUrl" data-phx-link="redirect" data-phx-link-state="push" class="v2-dock-btn">
      <Play class="size-5" />
    </a>
    <div class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">Play</div>
      <div class="text-xs text-muted-foreground leading-relaxed">Run this flow in story player</div>
    </div>
  </div>

  <!-- Debug -->
  <div class="v2-dock-item group relative">
    <button
      type="button"
      class="v2-dock-btn"
      :class="{ 'v2-dock-btn-active': debugPanelOpen }"
      @click="$emit('toggle-debug')"
    >
      <Bug class="size-5" />
    </button>
    <div class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">Debug</div>
      <div class="text-xs text-muted-foreground leading-relaxed">Step through flow execution</div>
    </div>
  </div>
</template>
