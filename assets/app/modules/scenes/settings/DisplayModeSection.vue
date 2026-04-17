<script setup lang="ts">
import { Maximize, Monitor, Scan } from "lucide-vue-next";
import { useLive } from "@composables/useLive";

const {
  displayMode = "fit",
  defaultZoom = 1.0,
  canEdit = false,
} = defineProps<{
  displayMode?: string;
  defaultZoom?: number;
  canEdit?: boolean;
}>();

const live = useLive();

function setMode(mode: string) {
  live.pushEvent("update_exploration_display_mode", { mode });
}

function onZoomBlur(e: FocusEvent) {
  live.pushEvent("update_scene_scale", {
    field: "default_zoom",
    value: (e.target as HTMLInputElement).value,
  });
}
</script>

<template>
  <div class="pt-2 border-t border-border space-y-2">
    <label class="text-xs font-medium text-foreground inline-flex items-center gap-1">
      <Monitor class="size-3" />
      {{ $t("scenes.settings.exploration_display") }}
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
        {{ $t("scenes.settings.fit") }}
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
        {{ $t("scenes.settings.scaled") }}
      </button>
    </div>
    <p class="text-xs text-muted-foreground/60">
      <template v-if="displayMode === 'scaled'">
        {{ $t("scenes.settings.scaled_desc") }}
      </template>
      <template v-else> {{ $t("scenes.settings.fit_desc") }} </template>
    </p>
    <div v-if="displayMode === 'scaled'" class="flex items-center gap-2 pt-1">
      <label class="text-xs text-muted-foreground whitespace-nowrap">{{ $t("scenes.settings.zoom") }}</label>
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
