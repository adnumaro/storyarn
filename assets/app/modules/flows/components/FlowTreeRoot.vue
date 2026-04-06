<script setup lang="ts">
import { makeDroppable } from "@vue-dnd-kit/core";
import { useTemplateRef } from "vue";
import type { FlowTreeItem } from "./FlowTree.vue";

const { items } = defineProps<{
  items: FlowTreeItem[];
}>();

const emit = defineEmits<{
  drop: [event: unknown];
}>();

const rootRef = useTemplateRef("rootRef");

makeDroppable(rootRef, { events: { onDrop: (e) => emit("drop", e) } }, () => items);
</script>

<template>
  <div ref="rootRef" class="space-y-0.5">
    <slot />
  </div>
</template>
