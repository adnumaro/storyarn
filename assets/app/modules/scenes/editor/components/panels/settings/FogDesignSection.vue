<script setup lang="ts">
import { CloudFog } from "lucide-vue-next";
import { computed } from "vue";
import { useLive } from "@shared/composables/useLive.ts";

const {
  fogColor = "#000000",
  fogOpacity = 0.85,
  canEdit = false,
} = defineProps<{
  fogColor?: string | null;
  fogOpacity?: number | null;
  canEdit?: boolean;
}>();

const live = useLive();

const opacity = computed(() => fogOpacity ?? 0.85);
const opacityPercent = computed(() => Math.round(opacity.value * 100));

function updateFogColor(event: Event): void {
  live.pushEvent("update_scene_fog", {
    field: "fog_color",
    value: (event.target as HTMLInputElement).value,
  });
}

function updateFogOpacity(event: Event): void {
  live.pushEvent("update_scene_fog", {
    field: "fog_opacity",
    value: (event.target as HTMLInputElement).value,
  });
}
</script>

<template>
  <div class="pt-2 border-t border-border space-y-2">
    <label class="text-xs font-medium text-foreground inline-flex items-center gap-1">
      <CloudFog class="size-3" />
      {{ $t("scenes.settings.fog_design") }}
    </label>

    <div class="grid grid-cols-[auto_1fr_auto] items-center gap-2">
      <label class="sr-only" for="scene-fog-color">
        {{ $t("scenes.settings.fog_color") }}
      </label>
      <input
        id="scene-fog-color"
        type="color"
        :value="fogColor || '#000000'"
        :disabled="!canEdit"
        class="size-7 rounded border border-border bg-transparent p-0 disabled:opacity-50"
        :title="$t('scenes.settings.fog_color')"
        @change="updateFogColor"
      />

      <label class="sr-only" for="scene-fog-opacity">
        {{ $t("scenes.settings.fog_opacity") }}
      </label>
      <input
        id="scene-fog-opacity"
        type="range"
        min="0"
        max="1"
        step="0.05"
        :value="opacity"
        :disabled="!canEdit"
        class="w-full accent-primary disabled:opacity-50"
        :title="$t('scenes.settings.fog_opacity')"
        @change="updateFogOpacity"
      />

      <span class="w-9 text-right text-xs tabular-nums text-muted-foreground">
        {{ opacityPercent }}%
      </span>
    </div>

    <p class="text-xs text-muted-foreground/60">
      {{ $t("scenes.settings.fog_design_desc") }}
    </p>
  </div>
</template>
