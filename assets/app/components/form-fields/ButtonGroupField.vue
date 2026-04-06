<script setup lang="ts">
import type { Component } from "vue";

interface ButtonOption {
  id?: string | number;
  value?: string | number;
  name?: string;
  label?: string;
}

const { label = "", icon = null, options, value = "", disabled = false } = defineProps<{
  label?: string;
  icon?: Component | null;
  options: ButtonOption[];
  value?: string | number;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  update: [value: string | number];
}>();
</script>

<template>
  <div class="space-y-1.5">
    <label
      v-if="label"
      class="block text-xs font-medium text-foreground/70 flex items-center gap-1"
    >
      <component :is="icon" v-if="icon" class="size-3" />
      {{ label }}
    </label>
    <div class="flex gap-0.5">
      <button
        v-for="opt in options"
        :key="opt.id ?? opt.value"
        type="button"
        class="px-2 py-1 text-xs rounded cursor-pointer transition-colors"
        :class="
          (opt.id ?? opt.value) === value ? 'bg-primary text-primary-foreground' : 'hover:bg-accent'
        "
        :disabled="disabled"
        @click="emit('update', opt.id ?? opt.value)"
      >
        {{ opt.name ?? opt.label }}
      </button>
    </div>
  </div>
</template>
