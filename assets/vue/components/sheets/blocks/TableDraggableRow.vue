<script setup>
import { useTemplateRef } from "vue";
import { makeDraggable } from "@vue-dnd-kit/core";

const props = defineProps({
	index: { type: Number, required: true },
	items: { type: Array, required: true },
	group: { type: String, required: true },
});

const rowRef = useTemplateRef("rowRef");

const { isDragging, isDragOver } = makeDraggable(
	rowRef,
	{
		dragHandle: ".row-drag-handle",
		groups: [props.group],
	},
	() => [props.index, props.items],
);
</script>

<template>
  <tr
    ref="rowRef"
    class="group/row border-b border-border last:border-b-0 relative"
    :class="{
      'opacity-30': isDragging,
      'shadow-[inset_0_2px_0_0_hsl(var(--primary))]': isDragOver?.top,
      'shadow-[inset_0_-2px_0_0_hsl(var(--primary))]': isDragOver?.bottom,
    }"
  >
    <slot :is-drag-over="isDragOver" />
  </tr>
</template>
