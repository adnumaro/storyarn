<script setup lang="ts">
import { makeDraggable } from "@vue-dnd-kit/core";
import { Grip, GripVertical } from "lucide-vue-next";
import { computed, onMounted, onUnmounted, ref, useTemplateRef } from "vue";

export interface DndItemData {
  kind: "full_width" | "column_child" | "group";
  blockId?: number | string;
  groupId?: string;
}

const {
  kind,
  blockId,
  groupId,
  canEdit = false,
  indicatorAxis = "both",
} = defineProps<{
  kind: "full_width" | "column_child" | "group";
  blockId?: number | string;
  groupId?: string;
  canEdit?: boolean;
  /** 'both' = top/bottom + left/right; 'vertical' = only top/bottom (groups). */
  indicatorAxis?: "both" | "vertical";
}>();

const itemRef = useTemplateRef("itemRef");

const data = computed<DndItemData>(() => ({ kind, blockId, groupId }));

const { isDragging, isDragOver } = makeDraggable(
  itemRef,
  {
    dragHandle: ".block-drag-handle",
    groups: ["sheet-blocks"],
    data: () => data.value,
  },
  () => [0, []] as [number, unknown[]],
);

// Track pointer X/Y relative to the element while hovered so we can decide
// horizontal vs vertical intent. vue-dnd-kit's placementMargins only supports
// a center-zone (no flags) which doesn't match the "sides trigger column /
// middle triggers vertical reorder" UX we want.
const SIDE_THRESHOLD = 0.25;
const relX = ref(0.5);
const relY = ref(0.5);

function onPointerMove(e: PointerEvent): void {
  const el = itemRef.value;
  if (!el || !isDragOver.value) return;
  const rect = (el as HTMLElement).getBoundingClientRect();
  relX.value = (e.clientX - rect.left) / rect.width;
  relY.value = (e.clientY - rect.top) / rect.height;
}

onMounted(() => document.addEventListener("pointermove", onPointerMove));
onUnmounted(() => document.removeEventListener("pointermove", onPointerMove));

const atSide = computed<"left" | "right" | null>(() => {
  if (!isDragOver.value || indicatorAxis === "vertical") return null;
  if (relX.value <= SIDE_THRESHOLD) return "left";
  if (relX.value >= 1 - SIDE_THRESHOLD) return "right";
  return null;
});

const atVertical = computed<"top" | "bottom" | null>(() => {
  if (!isDragOver.value || atSide.value) return null;
  return relY.value < 0.5 ? "top" : "bottom";
});

const showTop = computed(() => atVertical.value === "top");
const showBottom = computed(() => atVertical.value === "bottom");
const showLeft = computed(() => atSide.value === "left");
const showRight = computed(() => atSide.value === "right");
</script>

<template>
  <div
    ref="itemRef"
    class="group/dnd relative h-full [&>*:last-child]:h-full"
    :class="{ 'opacity-30': isDragging }"
  >
    <div
      v-if="showTop"
      class="pointer-events-none absolute -top-1.5 left-0 right-0 h-0.5 bg-primary rounded-full z-30"
      aria-hidden
    />
    <div
      v-if="showBottom"
      class="pointer-events-none absolute -bottom-1.5 left-0 right-0 h-0.5 bg-primary rounded-full z-30"
      aria-hidden
    />
    <div
      v-if="showLeft"
      class="pointer-events-none absolute left-0 top-0 bottom-0 w-1 bg-primary rounded-full z-30"
      aria-hidden
    />
    <div
      v-if="showRight"
      class="pointer-events-none absolute right-0 top-0 bottom-0 w-1 bg-primary rounded-full z-30"
      aria-hidden
    />

    <div
      v-if="canEdit && kind === 'group'"
      class="block-drag-handle absolute top-6 -left-5 cursor-grab active:cursor-grabbing text-muted-foreground/50 hover:text-muted-foreground opacity-0 group-hover/dnd:opacity-100 transition-opacity"
    >
      <Grip class="size-4" />
    </div>

    <div
      v-if="canEdit && kind !== 'group'"
      class="block-drag-handle absolute top-5.5 right-5 z-10 cursor-grab active:cursor-grabbing text-muted-foreground/50 hover:text-muted-foreground opacity-0 group-hover/dnd:opacity-100 transition-opacity"
    >
      <GripVertical class="size-4" />
    </div>

    <slot />
  </div>
</template>
