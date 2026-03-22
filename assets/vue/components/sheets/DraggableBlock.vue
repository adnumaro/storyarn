<script setup>
import { computed, ref, onMounted, onUnmounted, useTemplateRef } from "vue"
import { makeDraggable } from "@vue-dnd-kit/core"

const SIDE_THRESHOLD = 0.25

const props = defineProps({
  canEdit: { type: Boolean, default: false },
  index: { type: Number, required: true },
  items: { type: Array, required: true },
})

const itemRef = useTemplateRef("itemRef")

const { isDragging, isDragOver } = makeDraggable(itemRef, {
  dragHandle: ".drag-handle",
  groups: ["blocks-vertical"],
}, () => [props.index, props.items])

const isFullWidth = computed(() => props.items[props.index]?.type === "full_width")

const pointerRelX = ref(0.5)

function onPointerMove(e) {
  const el = itemRef.value
  if (!el || !isDragOver.value) return
  const rect = el.getBoundingClientRect()
  pointerRelX.value = (e.clientX - rect.left) / rect.width
}

onMounted(() => document.addEventListener("pointermove", onPointerMove))
onUnmounted(() => document.removeEventListener("pointermove", onPointerMove))

const atSide = computed(() => {
  if (!isDragOver.value || !isFullWidth.value) return null
  if (pointerRelX.value <= SIDE_THRESHOLD) return "left"
  if (pointerRelX.value >= 1 - SIDE_THRESHOLD) return "right"
  return null
})

const showTop = computed(() => isDragOver.value?.top && !atSide.value)
const showBottom = computed(() => isDragOver.value?.bottom && !atSide.value)
</script>

<template>
  <div
    ref="itemRef"
    class="group/drag relative flex items-start gap-0"
    :class="{ 'opacity-30': isDragging }"
  >
    <!-- Drop indicator: top (vertical reorder) -->
    <div
      v-if="showTop"
      class="absolute -top-1.5 left-0 right-0 h-0.5 bg-primary rounded-full z-20"
      aria-hidden
    />

    <!-- Drop indicator: bottom (vertical reorder) -->
    <div
      v-if="showBottom"
      class="absolute -bottom-1.5 left-0 right-0 h-0.5 bg-primary rounded-full z-20"
      aria-hidden
    />

    <!-- Drop indicator: left (create column group) -->
    <div
      v-if="atSide === 'left'"
      class="pointer-events-none absolute left-0 top-0 bottom-0 w-1 bg-primary rounded-full z-20"
      aria-hidden
    />

    <!-- Drop indicator: right (create column group) -->
    <div
      v-if="atSide === 'right'"
      class="pointer-events-none absolute right-0 top-0 bottom-0 w-1 bg-primary rounded-full z-20"
      aria-hidden
    />

    <!-- Drag handle -->
    <div
      v-if="canEdit"
      class="drag-handle flex items-center pt-6 pr-1 cursor-grab active:cursor-grabbing text-muted-foreground/30 hover:text-muted-foreground opacity-0 group-hover/drag:opacity-100 transition-opacity shrink-0"
    >
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="9" cy="12" r="1"/><circle cx="9" cy="5" r="1"/><circle cx="9" cy="19" r="1"/>
        <circle cx="15" cy="12" r="1"/><circle cx="15" cy="5" r="1"/><circle cx="15" cy="19" r="1"/>
      </svg>
    </div>

    <!-- Content -->
    <div class="flex-1 min-w-0 w-full overflow-hidden">
      <slot />
    </div>
  </div>
</template>
