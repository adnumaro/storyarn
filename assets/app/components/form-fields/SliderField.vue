<script setup>
import { computed } from "vue";

const { label, value, min, max, step, disabled, format } = defineProps({
  label: { type: String, default: "" },
  value: { type: [Number, String], default: 0 },
  min: { type: Number, default: 0 },
  max: { type: Number, default: 1 },
  step: { type: Number, default: 0.1 },
  disabled: { type: Boolean, default: false },
  format: { type: Function, default: null },
});

const emit = defineEmits(["update"]);

const displayValue = computed(() => {
  if (format) return format(Number(value));
  return value;
});
</script>

<template>
  <div class="space-y-1">
    <div class="flex items-center justify-between">
      <label v-if="label" class="text-xs font-medium text-foreground/70">{{ label }}</label>
      <span class="text-xs font-mono text-muted-foreground">{{ displayValue }}</span>
    </div>
    <input
      type="range"
      :value="value"
      :min="min"
      :max="max"
      :step="step"
      :disabled="disabled"
      class="w-full h-1 accent-primary disabled:opacity-40"
      @input="(e) => emit('update', e.target.value)"
    />
  </div>
</template>
