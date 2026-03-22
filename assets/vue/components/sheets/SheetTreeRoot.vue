<script setup>
import { useTemplateRef } from "vue";
import { makeDroppable } from "@vue-dnd-kit/core";

const props = defineProps({
	items: { type: Array, required: true },
});

const emit = defineEmits(["drop"]);

const rootRef = useTemplateRef("rootRef");

makeDroppable(
	rootRef,
	{ events: { onDrop: (e) => emit("drop", e) } },
	() => props.items,
);
</script>

<template>
  <div ref="rootRef" class="space-y-0.5">
    <slot />
  </div>
</template>
