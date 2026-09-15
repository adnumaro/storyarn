<script setup lang="ts">
import { computed } from "vue";
import { MessageCircle, Plus } from "@lucide/vue";

/**
 * A comment pin on a canvas: the teal speech bubble, with rings for the
 * selected and unread states, a dashed draft and a reply-count badge.
 */
const {
  draft = false,
  selected = false,
  movable = false,
  unread = false,
  count = 0,
} = defineProps<{
  draft?: boolean;
  selected?: boolean;
  movable?: boolean;
  unread?: boolean;
  /** Replies beyond the root; hidden at zero. */
  count?: number;
}>();

const bubble = computed(() => {
  if (draft)
    return "border-2 border-dashed border-primary bg-card text-primary shadow-[0_0_0_6px_hsl(var(--primary)/.14)]";
  if (selected)
    return "border-2 border-card bg-primary text-primary-foreground shadow-[0_0_0_3px_hsl(var(--card)),0_0_0_5px_hsl(var(--primary)),0_0_0_9px_hsl(var(--primary)/.15)]";
  if (unread)
    return "border-2 border-card bg-primary text-primary-foreground shadow-[0_0_0_2px_hsl(var(--card)),0_0_0_4px_hsl(var(--primary)/.55)]";
  return "border-2 border-card bg-primary text-primary-foreground shadow-md";
});
</script>

<template>
  <button
    type="button"
    class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 touch-none items-center justify-center rounded-[16px_16px_16px_4px] transition-[transform,box-shadow] hover:scale-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
    :class="[bubble, { 'cursor-grab active:cursor-grabbing': movable }]"
    :aria-haspopup="draft ? undefined : 'dialog'"
    :data-comment-pin-unread="unread || undefined"
  >
    <Plus v-if="draft" class="size-4" />
    <MessageCircle v-else class="size-4" />
    <span
      v-if="!draft && unread"
      class="absolute -right-1 -top-1 size-3 rounded-full border-2 border-card bg-primary"
      aria-hidden="true"
    />
    <span
      v-if="!draft && count > 0"
      class="absolute -bottom-1.5 -right-2 flex h-[18px] min-w-[18px] items-center justify-center rounded-full border-2 border-card bg-foreground px-1 text-[10px] font-bold tabular-nums text-background"
      aria-hidden="true"
      >{{ count }}</span
    >
  </button>
</template>
