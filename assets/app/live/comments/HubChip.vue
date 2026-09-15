<script setup lang="ts">
import type { Component } from "vue";

/** A filter chip: optional icon, label, facet count and pressed state. */
const {
  active = false,
  count = null,
  icon = null,
  iconClass = "",
  dot = false,
} = defineProps<{
  active?: boolean;
  count?: number | null;
  icon?: Component | null;
  iconClass?: string;
  /** A teal dot instead of an icon (the unread marker). */
  dot?: boolean;
}>();
</script>

<template>
  <button
    type="button"
    class="inline-flex h-7 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
    :class="
      active
        ? 'bg-primary/15 text-primary'
        : 'text-muted-foreground hover:bg-accent hover:text-foreground'
    "
    :aria-pressed="active"
  >
    <span v-if="dot" class="size-[7px] rounded-full bg-primary" aria-hidden="true" />
    <component :is="icon" v-else-if="icon" class="size-3" :class="iconClass" />
    <slot />
    <span v-if="count != null" class="tabular-nums opacity-75">{{ count }}</span>
  </button>
</template>
