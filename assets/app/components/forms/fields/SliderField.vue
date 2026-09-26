<script setup lang="ts">
import { computed, ref } from "vue";

const {
  label = "",
  value = 0,
  min = 0,
  max = 1,
  step = 0.1,
  disabled = false,
  format = null,
} = defineProps<{
  label?: string;
  value?: number | string;
  min?: number;
  max?: number;
  step?: number;
  disabled?: boolean;
  format?: ((value: number) => string) | null;
}>();

const emit = defineEmits<{
  update: [value: string];
}>();

// The label follows the thumb while dragging; the value is committed on release.
const draft = ref<string | null>(null);

const displayValue = computed(() => {
  const current = draft.value ?? value;
  if (format) return format(Number(current));
  return current;
});

function commit(event: Event): void {
  draft.value = null;
  emit("update", (event.target as HTMLInputElement).value);
}
</script>

<template>
  <div class="space-y-1">
    <div class="flex items-center justify-between">
      <label v-if="label" class="text-xs font-medium text-foreground/70">{{ label }}</label>
      <span class="text-xs font-mono text-muted-foreground">{{ displayValue }}</span>
    </div>
    <input
      type="range"
      :value="draft ?? value"
      :min="min"
      :max="max"
      :step="step"
      :disabled="disabled"
      class="w-full h-1 accent-primary disabled:opacity-40"
      @input="(e: Event) => (draft = (e.target as HTMLInputElement).value)"
      @change="commit"
    />
  </div>
</template>
