<script setup lang="ts">
import type { Component } from "vue";
import { Switch } from "@components/ui/switch";

const { label = "", icon = null, checked = false, disabled = false } = defineProps<{
  label?: string;
  icon?: Component | null;
  checked?: boolean;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  toggle: [];
}>();
</script>

<template>
  <div class="flex items-center justify-between">
    <label class="text-xs font-medium text-foreground/70 flex items-center gap-1">
      <component :is="icon" v-if="icon" class="size-3" />
      {{ label }}
    </label>
    <Switch :model-value="checked" :disabled="disabled" @update:model-value="emit('toggle')" />
  </div>
</template>
