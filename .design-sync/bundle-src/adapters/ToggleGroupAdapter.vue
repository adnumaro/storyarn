<script setup lang="ts">
/**
 * Props-driven facade over the app's ToggleGroup compound.
 * Note: reka-ui emits `undefined` when a single-type group is fully
 * deselected — the adapter passes that through; keep your state nullable.
 */
import { ToggleGroup, ToggleGroupItem } from "@components/ui/toggle-group";

export interface ToggleGroupOption {
  value: string;
  label: string;
  disabled?: boolean;
}

const {
  items = [],
  type = "single",
  variant = "outline",
  size = "default",
} = defineProps<{
  items?: ToggleGroupOption[];
  type?: "single" | "multiple";
  variant?: "default" | "outline";
  size?: "default" | "sm" | "lg";
  class?: string;
}>();

const modelValue = defineModel<string | string[]>();
</script>

<template>
  <ToggleGroup v-model="modelValue" :type="type" :class="$props.class">
    <ToggleGroupItem
      v-for="item in items"
      :key="item.value"
      :value="item.value"
      :disabled="item.disabled"
      :variant="variant"
      :size="size"
    >
      {{ item.label }}
    </ToggleGroupItem>
  </ToggleGroup>
</template>
