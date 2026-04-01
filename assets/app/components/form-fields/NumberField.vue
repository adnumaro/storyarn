<script setup>
const { label, value, min, max, step, disabled } = defineProps({
  label: { type: String, default: "" },
  value: { type: [Number, String], default: 0 },
  min: { type: Number, default: 0 },
  max: { type: Number, default: 100 },
  step: { type: Number, default: 1 },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update"]);
</script>

<template>
  <div class="space-y-1">
    <label v-if="label" class="block text-xs font-medium text-foreground/70">{{ label }}</label>
    <input
      type="number"
      :value="value"
      :min="min"
      :max="max"
      :step="step"
      :disabled="disabled"
      class="w-full text-sm px-2 py-1.5 rounded-md border border-input bg-background dark:bg-card shadow-xs focus:outline-none focus:ring-1 focus:ring-ring disabled:opacity-50 disabled:cursor-not-allowed"
      @change="(e) => emit('update', e.target.value)"
    />
  </div>
</template>
