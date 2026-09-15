<script setup lang="ts">
import type { Component } from "vue";
import { CheckCheck, CircleAlert, CircleDot, Unlink } from "@lucide/vue";

export type CommentPillKind =
  | "open"
  | "resolved"
  | "draft"
  | "context-removed"
  | "source-unavailable";

const { kind } = defineProps<{ kind: CommentPillKind }>();

const styles: Record<CommentPillKind, { icon: Component | null; classes: string }> = {
  open: { icon: CircleDot, classes: "bg-primary/10 text-primary" },
  resolved: { icon: CheckCheck, classes: "bg-[hsl(150_45%_52%/.14)] text-[hsl(150_45%_55%)]" },
  draft: { icon: null, classes: "bg-muted text-muted-foreground" },
  "context-removed": { icon: Unlink, classes: "bg-[hsl(24_85%_60%/.14)] text-[hsl(24_85%_62%)]" },
  "source-unavailable": {
    icon: CircleAlert,
    classes: "bg-[hsl(24_85%_60%/.14)] text-[hsl(24_85%_62%)]",
  },
};
</script>

<template>
  <span
    class="inline-flex h-5 shrink-0 items-center gap-1 whitespace-nowrap rounded-full px-1.5 text-[11px] font-medium"
    :class="styles[kind].classes"
    :data-comment-pill="kind"
  >
    <component :is="styles[kind].icon" v-if="styles[kind].icon" class="size-[11px]" />
    <slot />
  </span>
</template>
