<script setup lang="ts">
import { MessageCircle, Plus } from "@lucide/vue";

const {
  draft = false,
  selected = false,
  movable = false,
} = defineProps<{
  draft?: boolean;
  selected?: boolean;
  movable?: boolean;
}>();
</script>

<template>
  <button
    type="button"
    class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 touch-none items-center justify-center rounded-full rounded-bl-sm border-2 border-background bg-primary text-primary-foreground shadow-md transition-[background-color,transform] hover:scale-105 hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
    :class="{
      'ring-2 ring-primary/40': draft,
      'ring-2 ring-ring ring-offset-2': selected,
      'cursor-grab active:cursor-grabbing': movable,
    }"
    :aria-haspopup="draft ? undefined : 'dialog'"
  >
    <Plus v-if="draft" class="size-4" />
    <MessageCircle v-else class="size-4" />
  </button>
</template>
