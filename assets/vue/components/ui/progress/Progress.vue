<script setup>
import { computed } from "vue";
import { ProgressIndicator, ProgressRoot } from "reka-ui";
import { cn } from "@/vue/lib/utils";

const props = defineProps({
	modelValue: { type: Number, default: 0 },
	max: { type: Number, default: 100 },
	class: {
		type: [Boolean, null, String, Object, Array],
		required: false,
		skipCheck: true,
	},
});

const percentage = computed(() => {
	const val = Math.min(props.modelValue, props.max);
	return props.max > 0 ? (val / props.max) * 100 : 0;
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
