<script setup lang="ts">
import { makeDraggable } from "@vue-dnd-kit/core";
import { useTemplateRef } from "vue";
import type { TableRow } from "../../../types";

const { index, items, group } = defineProps<{
  index: number;
  items: TableRow[];
  group: string;
}>();

const rowRef = useTemplateRef("rowRef");

const { isDragging, isDragOver } = makeDraggable(
  rowRef,
  {
    dragHandle: ".row-drag-handle",
    groups: [group],
  },
  () => [index, items],
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
