<script setup lang="ts">
import { makeDroppable } from "@vue-dnd-kit/core";
import { useTemplateRef } from "vue";

interface TreeItem {
  id: number | string;
  name: string;
  children?: TreeItem[];
}

/* eslint-disable @typescript-eslint/no-explicit-any */
const { items } = defineProps<{
  items: TreeItem[];
}>();

const emit = defineEmits<{
  drop: [e: any];
}>();

const rootRef = useTemplateRef("rootRef");

makeDroppable(rootRef, { events: { onDrop: (e: any) => emit("drop", e) } }, () => items);
</script>

<template>
  <div ref="rootRef" class="space-y-0.5">
    <slot />
  </div>
</template>
