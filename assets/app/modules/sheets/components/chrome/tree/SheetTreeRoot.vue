<script setup lang="ts">
import { makeDroppable } from "@vue-dnd-kit/core";
import { useTemplateRef } from "vue";
import type { SheetTreeNodeData } from "../../../types";

const { items } = defineProps<{
  items: SheetTreeNodeData[];
}>();

const emit = defineEmits<{
  drop: [event: unknown];
}>();

const rootRef = useTemplateRef("rootRef");

makeDroppable(rootRef, { events: { onDrop: (e: unknown) => emit("drop", e) } }, () => items);
</script>

<template>
  <div ref="rootRef" class="space-y-0.5">
    <slot />
  </div>
</template>
