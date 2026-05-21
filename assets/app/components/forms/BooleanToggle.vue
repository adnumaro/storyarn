<script setup lang="ts">
/**
 * Shared boolean editor used by sheets BooleanBlock and the flow debug panel.
 *
 * - `two_state`: renders a Switch + label.
 * - `tri_state`: renders a cycle button with a colored dot (green / red /
 *   neutral grey) and label. Click cycles true → false → null → true.
 *
 * Emits `update:value` with `boolean | null`. Labels are supplied by the
 * caller so each surface can use its own i18n strings or per-block overrides.
 */

import { computed } from "vue";
import { Switch } from "@components/ui/switch";

type BooleanValue = boolean | null;
type BooleanMode = "two_state" | "tri_state";

const {
  value,
  mode = "two_state",
  trueLabel,
  falseLabel,
  neutralLabel = "—",
  disabled = false,
} = defineProps<{
  value: BooleanValue;
  mode?: BooleanMode;
  trueLabel: string;
  falseLabel: string;
  neutralLabel?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:value": [value: BooleanValue];
}>();

const label = computed(() => {
  if (value === true) return trueLabel;
  if (value === false) return falseLabel;
  return neutralLabel;
});

function onSwitchChange(v: boolean) {
  emit("update:value", v);
}

function cycle() {
  if (disabled) return;
  let next: BooleanValue;
  if (value === true) next = false;
  else if (value === false) next = null;
  else next = true;
  emit("update:value", next);
}
</script>

<template>
  <!-- Two-state -->
  <div v-if="mode === 'two_state'" class="flex items-center gap-3">
    <Switch
      :model-value="value === true"
      :disabled="disabled"
      @update:model-value="onSwitchChange"
    />
    <span class="text-sm text-muted-foreground">{{ label }}</span>
  </div>

  <!-- Tri-state cycle button -->
  <button
    v-else
    type="button"
    :disabled="disabled"
    class="inline-flex items-center gap-2 px-3 py-1.5 rounded-md border border-border text-sm hover:bg-accent transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
    @click="cycle"
  >
    <span
      class="size-2.5 rounded-full"
      :class="{
        'bg-green-500': value === true,
        'bg-red-500': value === false,
        'bg-muted-foreground/30': value == null,
      }"
    />
    {{ label }}
  </button>
</template>
