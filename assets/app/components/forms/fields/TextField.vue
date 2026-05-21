<script setup lang="ts">
const {
  label = "",
  value = "",
  placeholder = "",
  disabled = false,
} = defineProps<{
  label?: string;
  value?: string;
  placeholder?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  update: [value: string];
}>();
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
      @blur="(e: Event) => emit('update', (e.target as HTMLInputElement).value)"
      @keydown.enter="($event.target as HTMLInputElement).blur()"
    />
  </div>
</template>
