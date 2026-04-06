<script setup lang="ts">
import type { HTMLAttributes } from "vue";
import { ProgressIndicator, ProgressRoot } from "reka-ui";
import { computed } from "vue";
import { cn } from "@utils/utils";

const props = defineProps<{
  modelValue?: number;
  max?: number;
  class?: HTMLAttributes["class"];
}>();

const percentage = computed(() => {
  const max = props.max ?? 100;
  const modelValue = props.modelValue ?? 0;
  const val = Math.min(modelValue, max);
  return max > 0 ? (val / max) * 100 : 0;
});
</script>

<template>
  <ProgressRoot
    :model-value="modelValue"
    :max="max"
    :class="cn('relative h-2 w-full overflow-hidden rounded-full bg-primary/20', props.class)"
  >
    <ProgressIndicator
      class="h-full bg-primary transition-all duration-300 ease-in-out"
      :style="{ width: `${percentage}%` }"
    />
  </ProgressRoot>
</template>
