<script setup lang="ts">
import { Bug, History, Play, Square } from "@lucide/vue";

const { debugPanelOpen = false, visualEditorOpen = false } = defineProps<{
  debugPanelOpen: boolean;
  visualEditorOpen: boolean;
}>();

const emit = defineEmits<{
  "open-versions": [];
  "toggle-visual-editor": [];
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
    <button
      type="button"
      class="dock-btn"
      :class="{ 'dock-btn-active': visualEditorOpen }"
      :aria-label="visualEditorOpen ? $t('flows.dock.stop') : $t('flows.dock.play')"
      data-toggle-visual-editor
      @click="$emit('toggle-visual-editor')"
    >
      <Square v-if="visualEditorOpen" class="size-4 fill-current" data-stop-icon />
      <Play v-else class="size-5" data-play-icon />
    </button>
    <div class="dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">
        {{ visualEditorOpen ? $t("flows.dock.stop") : $t("flows.dock.play") }}
      </div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        {{ visualEditorOpen ? $t("flows.dock.stop_desc") : $t("flows.dock.play_desc") }}
      </div>
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
      <div class="text-xs text-muted-foreground leading-relaxed">
        {{ $t("flows.dock.debug_desc") }}
      </div>
    </div>
  </div>
</template>
