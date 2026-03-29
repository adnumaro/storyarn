<script setup>
import { computed } from "@/vue/index.js";

const props = defineProps({
	color: { type: String, default: "#3b82f6" },
	selected: { type: Boolean, default: false },
	extraClass: { type: String, default: "" },
});

const borderColor = computed(() => `${props.color}40`);
</script>

<template>
  <div
    class="node relative bg-background rounded-xl min-w-[180px] border-[1.5px]"
    :class="[selected && 'selected', extraClass]"
    :style="{ borderColor, '--node-border-color': borderColor, '--node-color': color }"
    data-testid="node"
  >
    <slot />
  </div>
</template>
