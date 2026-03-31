<script setup>
import { Maximize, Monitor, Scan } from "lucide-vue-next";
import { useLive } from "@composables/useLive";

const props = defineProps({
  displayMode: { type: String, default: "fit" },
  defaultZoom: { type: Number, default: 1.0 },
  canEdit: { type: Boolean, default: false },
});

const live = useLive();

function setMode(mode) {
  live.pushEvent("update_exploration_display_mode", { mode });
}

function onZoomBlur(e) {
  live.pushEvent("update_scene_scale", {
    field: "default_zoom",
    value: e.target.value,
  });
}
</script>

<template>
  <div class="pt-2 border-t border-border space-y-2">
    <label class="text-xs font-medium text-foreground inline-flex items-center gap-1">
      <Monitor class="size-3" />
      Exploration Display
    </label>
    <div class="flex gap-1">
      <button
        type="button"
        :class="[
          'flex-1 inline-flex items-center justify-center gap-1 h-7 text-xs rounded-md transition-colors',
          displayMode !== 'scaled'
            ? 'bg-primary text-primary-foreground'
            : 'bg-transparent text-muted-foreground hover:bg-accent hover:text-foreground',
        ]"
        @click="setMode('fit')"
      >
        <Maximize class="size-3" />
        Fit
      </button>
      <button
        type="button"
        :class="[
          'flex-1 inline-flex items-center justify-center gap-1 h-7 text-xs rounded-md transition-colors',
          displayMode === 'scaled'
            ? 'bg-primary text-primary-foreground'
            : 'bg-transparent text-muted-foreground hover:bg-accent hover:text-foreground',
        ]"
        @click="setMode('scaled')"
      >
        <Scan class="size-3" />
        Scaled
      </button>
    </div>
    <p class="text-xs text-muted-foreground/60">
      <template v-if="displayMode === 'scaled'">
        Renders at native pixel size with CRPG-style camera scrolling.
      </template>
      <template v-else> Scales to fit the viewport. </template>
    </p>
    <div v-if="displayMode === 'scaled'" class="flex items-center gap-2 pt-1">
      <label class="text-xs text-muted-foreground whitespace-nowrap">Zoom</label>
      <input
        type="number"
        min="0.5"
        max="10"
        step="0.5"
        :value="defaultZoom || 1.0"
        :disabled="!canEdit"
        class="flex-1 h-7 px-2 text-xs rounded-md border border-input bg-background"
        @blur="onZoomBlur"
      />
      <span class="text-xs text-muted-foreground/60">&times;</span>
    </div>
  </div>
</template>
