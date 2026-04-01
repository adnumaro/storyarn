<script setup>
import { Ruler } from "lucide-vue-next";
import { computed } from "vue";
import { useLive } from "@composables/useLive";

const { scaleValue, scaleUnit } = defineProps({
  scaleValue: { type: [Number, String], default: null },
  scaleUnit: { type: String, default: null },
});

const live = useLive();

const formattedScale = computed(() => {
  if (!scaleValue || !scaleUnit) return null;
  const v = Number(scaleValue);
  const display = Number.isFinite(v) && v === Math.floor(v) ? Math.trunc(v) : v;
  return `1 scene width = ${display} ${scaleUnit}`;
});

function onBlur(field, e) {
  live.pushEvent("update_scene_scale", { field, value: e.target.value });
}
</script>

<template>
  <div class="pt-2 border-t border-border space-y-2">
    <label class="text-xs font-medium text-foreground inline-flex items-center gap-1">
      <Ruler class="size-3" />
      Scene Scale
    </label>
    <div class="grid grid-cols-2 gap-2">
      <div>
        <label class="text-xs text-muted-foreground/70">Total width</label>
        <input
          type="number"
          min="0"
          step="any"
          :value="scaleValue ?? ''"
          placeholder="500"
          class="w-full h-7 px-2 text-xs rounded-md border border-input bg-background"
          @blur="onBlur('scale_value', $event)"
        />
      </div>
      <div>
        <label class="text-xs text-muted-foreground/70">Unit</label>
        <input
          type="text"
          :value="(scaleValue && scaleUnit) || ''"
          placeholder="km"
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
