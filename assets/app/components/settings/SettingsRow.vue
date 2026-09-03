<script setup lang="ts">
/**
 * One setting: label and hint on the left, one control right-aligned.
 * `stacked` puts the control under the label (textareas); `control="input"`
 * gives the control the 280px column the design reserves for text inputs.
 */
const {
  label,
  hint = null,
  stacked = false,
  control = "auto",
  htmlFor = null,
} = defineProps<{
  label: string;
  hint?: string | null;
  stacked?: boolean;
  control?: "auto" | "input";
  htmlFor?: string | null;
}>();
</script>

<template>
  <div
    :class="[
      'px-4 py-3.5',
      stacked
        ? 'flex flex-col gap-2'
        : 'grid grid-cols-1 items-center gap-x-6 gap-y-2 sm:grid-cols-[minmax(0,1fr)_auto]',
    ]"
  >
    <div class="flex min-w-0 items-center gap-3">
      <slot name="leading" />
      <div class="min-w-0">
        <label v-if="htmlFor" :for="htmlFor" class="font-medium">{{ label }}</label>
        <div v-else class="font-medium">{{ label }}</div>
        <div v-if="hint || $slots.hint" class="text-[13px] text-muted-foreground">
          <slot name="hint">{{ hint }}</slot>
        </div>
      </div>
    </div>

    <div
      :class="[
        stacked ? 'w-full' : 'flex items-center justify-end gap-2',
        !stacked && control === 'input' && 'w-full sm:w-[280px] sm:max-w-full',
      ]"
    >
      <slot />
    </div>
  </div>
</template>
