<script setup lang="ts">
import { MessagesSquare } from "@lucide/vue";
import { onMounted, onUnmounted, ref } from "vue";
import { GLOBAL_SURFACE, registerPaletteCommands } from "@shared/command-palette/registry";
import { COMMENTS_VISIBILITY_EVENT, openComments } from "./commentsHubEvents";

const open = ref(false);
function syncVisibility(event: Event): void {
  open.value = (event as CustomEvent<{ open: boolean }>).detail.open;
}

const unregister = registerPaletteCommands(GLOBAL_SURFACE, [
  {
    id: "global.comments",
    labelKey: "comments_hub.title",
    groupKey: "palette.groups.navigation",
    icon: MessagesSquare,
    run: openComments,
  },
]);

onMounted(() => window.addEventListener(COMMENTS_VISIBILITY_EVENT, syncVisibility));
onUnmounted(() => {
  unregister();
  window.removeEventListener(COMMENTS_VISIBILITY_EVENT, syncVisibility);
});
</script>

<template>
  <button
    id="comments-hub-button"
    type="button"
    :aria-label="$t('comments_hub.title')"
    :title="$t('comments_hub.title')"
    aria-haspopup="dialog"
    :aria-expanded="open"
    :class="[
      'inline-flex size-9 shrink-0 items-center justify-center rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
      open
        ? 'bg-accent text-accent-foreground'
        : 'text-muted-foreground hover:bg-accent hover:text-foreground',
    ]"
    @click="openComments"
  >
    <MessagesSquare class="size-4" />
  </button>
</template>
