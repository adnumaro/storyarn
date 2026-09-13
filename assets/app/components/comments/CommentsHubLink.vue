<script setup lang="ts">
import { MessagesSquare } from "@lucide/vue";
import { onUnmounted, watch } from "vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { GLOBAL_SURFACE, registerPaletteCommands } from "@shared/command-palette/registry";

const { to = "/comments", active = false } = defineProps<{
  to?: string;
  active?: boolean;
}>();

let unregister: (() => void) | undefined;
watch(
  () => to,
  (href) => {
    unregister?.();
    unregister = registerPaletteCommands(GLOBAL_SURFACE, [
      {
        id: "global.comments",
        labelKey: "comments_hub.title",
        groupKey: "palette.groups.navigation",
        icon: MessagesSquare,
        href,
      },
    ]);
  },
  { immediate: true },
);
onUnmounted(() => unregister?.());
</script>

<template>
  <LiveLink
    id="comments-hub-link"
    :to="to"
    :aria-label="$t('comments_hub.title')"
    :title="$t('comments_hub.title')"
    :aria-current="active ? 'page' : undefined"
    :class="[
      'inline-flex size-9 shrink-0 items-center justify-center rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
      active
        ? 'bg-accent text-accent-foreground'
        : 'text-muted-foreground hover:bg-accent hover:text-foreground',
    ]"
  >
    <MessagesSquare class="size-4" />
  </LiveLink>
</template>
