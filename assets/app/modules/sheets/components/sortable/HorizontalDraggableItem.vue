<script setup lang="ts">
import { makeDraggable, makeDroppable } from "@vue-dnd-kit/core";
import type { IDragEvent } from "@vue-dnd-kit/core";
import { GripVertical } from "lucide-vue-next";
import { computed, useTemplateRef } from "vue";
import type { Block } from "../../types";

interface InsertFullWidthPayload {
  draggedBlockId: number | string;
  groupId: string;
  side: string;
  targetBlockId: number | string;
}

const {
  blockId,
  canEdit = false,
  groupId,
  index,
  items,
  group,
} = defineProps<{
  blockId: number | string;
  canEdit?: boolean;
  groupId: string;
  index: number;
  items: Block[];
  group: string;
}>();

const emit = defineEmits<{
  "insert-full-width": [payload: InsertFullWidthPayload];
}>();

const itemRef = useTemplateRef("itemRef");

const { isDragging, isDragOver: intraGroupPlacement } = makeDraggable(
  itemRef,
  {
    dragHandle: ".column-drag-handle",
    groups: [group, "blocks-vertical"],
  },
  () => [index, items],
);

function extractDropContext(e: IDragEvent) {
  const draggedItem = e.draggedItems?.[0]?.item as { type?: string; block?: Block } | undefined;
  const pointer = e.provider?.pointer?.value?.current;
  const rect = (itemRef.value as HTMLElement | null)?.getBoundingClientRect();
  return { draggedItem, pointer, rect };
}

function canAcceptDrop(
  draggedItem: { type?: string } | undefined,
  pointer: { x: number } | undefined,
  rect: DOMRect | undefined,
): boolean {
  return draggedItem?.type === "full_width" && !!pointer && !!rect && items.length < 3;
}

function computeDropSide(e: IDragEvent): string | null {
  const { draggedItem, pointer, rect } = extractDropContext(e);
  if (!canAcceptDrop(draggedItem, pointer, rect)) return null;

  return (pointer!.x - rect!.left) / rect!.width < 0.5 ? "left" : "right";
}

const { isDragOver: fullWidthPlacement } = makeDroppable(itemRef, {
  groups: ["blocks-vertical"],
  events: {
    onDrop: (e: IDragEvent) => {
      const side = computeDropSide(e);
      if (!side) return;

      const draggedItem = e.draggedItems?.[0]?.item as { type?: string; block?: Block };
      emit("insert-full-width", {
        draggedBlockId: draggedItem.block!.id,
        groupId: groupId,
        side,
        targetBlockId: blockId,
      });
    },
  },
});

const placement = computed(() => {
  if (
    fullWidthPlacement.value &&
    items.length < 3 &&
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
