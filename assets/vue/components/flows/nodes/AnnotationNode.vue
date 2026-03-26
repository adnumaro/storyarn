<script setup>
import { computed } from "vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
});

const nodeData = computed(() => props.data.nodeData || {});
const text = computed(() => nodeData.value.text || "…");
const annColor = computed(() => nodeData.value.color || "#fbbf24");

const sizeClass = computed(() => {
	const fs = nodeData.value.font_size;
	if (fs === "sm" || fs === "small") return "text-xs";
	if (fs === "lg" || fs === "large") return "text-base";
	return "text-sm";
});
</script>

<template>
  <div
    class="annotation relative min-w-[120px] max-w-[280px] rounded-lg shadow-md"
    :style="{ '--ann-color': annColor }"
    data-testid="node"
  >
    <div
      class="absolute inset-0 rounded-lg opacity-90"
      :style="{ backgroundColor: annColor }"
    />
    <div
      :class="['relative px-3 py-2 text-gray-900 whitespace-pre-wrap break-words leading-relaxed', sizeClass]"
    >
      {{ text }}
    </div>
    <!-- Corner fold -->
    <div
      class="absolute bottom-0 right-0 size-4 rounded-bl-lg"
      :style="{ backgroundColor: `color-mix(in oklch, ${annColor} 70%, black)` }"
    />
  </div>
</template>
