<script setup lang="ts">
import { computed } from "vue";

const {
  color = "#3b82f6",
  selected = false,
  extraClass = "",
} = defineProps<{
  color?: string;
  selected?: boolean;
  extraClass?: string;
}>();

const borderColor = computed(() => `${color}40`);
</script>

<template>
  <div
    class="node relative bg-background rounded-xl min-w-45 border-[1.5px]"
    :class="[selected && 'selected', extraClass]"
    :style="{ borderColor, '--node-border-color': borderColor, '--node-color': color }"
    data-testid="node"
  >
    <slot />
  </div>
</template>
