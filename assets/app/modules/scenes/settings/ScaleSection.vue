<script setup lang="ts">
import { Ruler } from "lucide-vue-next";
import { computed } from "vue";
import { useLive } from "@composables/useLive";

const { scaleValue = null, scaleUnit = null } = defineProps<{
  scaleValue?: number | string | null;
  scaleUnit?: string | null;
}>();

const live = useLive();

const formattedScale = computed(() => {
  if (!scaleValue || !scaleUnit) return null;
  const v = Number(scaleValue);
  const display = Number.isFinite(v) && v === Math.floor(v) ? Math.trunc(v) : v;
  return `1 scene width = ${display} ${scaleUnit}`;
});

function onBlur(field: string, e: FocusEvent) {
  live.pushEvent("update_scene_scale", { field, value: (e.target as HTMLInputElement).value });
}
</script>

<template>
  <div class="pt-2 border-t border-border space-y-2">
    <label class="text-xs font-medium text-foreground inline-flex items-center gap-1">
      <Ruler class="size-3" />
      {{ $t("scenes.settings.scene_scale") }}
    </label>
    <div class="grid grid-cols-2 gap-2">
      <div>
        <label class="text-xs text-muted-foreground/70">{{
          $t("scenes.settings.total_width")
        }}</label>
        <input
          type="number"
          min="0"
          step="any"
          :value="scaleValue ?? ''"
          :placeholder="$t('scenes.settings.width_placeholder')"
          class="w-full h-7 px-2 text-xs rounded-md border border-input bg-background"
          @blur="onBlur('scale_value', $event)"
        />
      </div>
      <div>
        <label class="text-xs text-muted-foreground/70">{{ $t("scenes.settings.unit") }}</label>
        <input
          type="text"
          :value="(scaleValue && scaleUnit) || ''"
          :placeholder="$t('scenes.settings.unit_placeholder')"
          class="w-full h-7 px-2 text-xs rounded-md border border-input bg-background"
          @blur="onBlur('scale_unit', $event)"
        />
      </div>
    </div>
    <p v-if="formattedScale" class="text-xs text-muted-foreground/60">
      {{ formattedScale }}
    </p>
  </div>
</template>
