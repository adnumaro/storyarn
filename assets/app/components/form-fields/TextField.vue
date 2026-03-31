<script setup>
defineProps({
  label: { type: String, default: "" },
  value: { type: String, default: "" },
  placeholder: { type: String, default: "" },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update"]);
</script>

<template>
  <div class="space-y-1">
    <label v-if="label" class="block text-xs font-medium text-foreground/70">{{ label }}</label>
    <input
      type="text"
      :value="value"
      :placeholder="placeholder"
      :disabled="disabled"
      class="w-full text-sm px-2 py-1.5 rounded-md border border-input bg-background dark:bg-card shadow-xs focus:outline-none focus:ring-1 focus:ring-ring disabled:opacity-50 disabled:cursor-not-allowed"
      @blur="(e) => emit('update', e.target.value)"
      @keydown.enter="$event.target.blur()"
    />
  </div>
</template>
