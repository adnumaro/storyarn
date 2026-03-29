<script setup>
import { computed, useTemplateRef } from "@/vue/index.js";
import { makeDraggable, makeDroppable } from "@vue-dnd-kit/core";
import { GripVertical } from "lucide-vue-next";

const props = defineProps({
	blockId: { type: [Number, String], required: true },
	canEdit: { type: Boolean, default: false },
	groupId: { type: String, required: true },
	index: { type: Number, required: true },
	items: { type: Array, required: true },
	group: { type: String, required: true },
});

const emit = defineEmits(["insert-full-width"]);

const itemRef = useTemplateRef("itemRef");

const { isDragging, isDragOver: intraGroupPlacement } = makeDraggable(
	itemRef,
	{
		dragHandle: ".column-drag-handle",
		groups: [props.group, "blocks-vertical"],
	},
	() => [props.index, props.items],
);

const { isDragOver: fullWidthPlacement } = makeDroppable(itemRef, {
	groups: ["blocks-vertical"],
	events: {
		onDrop: (e) => {
			const draggedItem = e.draggedItems?.[0]?.item;
			const pointer = e.provider?.pointer?.value?.current;
			const rect = itemRef.value?.getBoundingClientRect();

			if (
				draggedItem?.type !== "full_width" ||
				!pointer ||
				!rect ||
				props.items.length >= 3
			) {
				return;
			}

			const relX = (pointer.x - rect.left) / rect.width;
			const side = relX < 0.5 ? "left" : "right";

			emit("insert-full-width", {
				draggedBlockId: draggedItem.block.id,
				groupId: props.groupId,
				side,
				targetBlockId: props.blockId,
			});
		},
	},
});

const placement = computed(() => {
	if (
		fullWidthPlacement.value &&
		props.items.length < 3 &&
		(fullWidthPlacement.value.left || fullWidthPlacement.value.right)
	) {
		return fullWidthPlacement.value;
	}

	return intraGroupPlacement.value;
});
</script>

<template>
  <div
    ref="itemRef"
    class="group/col relative h-full [&>*:last-child]:h-full"
    :class="{ 'opacity-30': isDragging }"
  >
    <!-- Drop indicator: left -->
    <div
      v-if="placement?.left"
      class="pointer-events-none absolute left-0 top-0 bottom-0 w-0.5 bg-primary rounded-full z-30"
      aria-hidden
    />

    <!-- Drop indicator: right -->
    <div
      v-if="placement?.right"
      class="pointer-events-none absolute right-0 top-0 bottom-0 w-0.5 bg-primary rounded-full z-30"
      aria-hidden
    />

    <!-- Block drag handle: absolute, left of block -->
    <div
      v-if="canEdit"
      class="column-drag-handle absolute -left-5 top-5 cursor-grab active:cursor-grabbing text-muted-foreground/50 hover:text-muted-foreground opacity-0 group-hover/col:opacity-100 transition-opacity"
    >
      <GripVertical class="size-4" />
    </div>

    <slot />
  </div>
</template>
