<script setup lang="ts">
import { useLive } from "@shared/composables/useLive";
import CommentConversation from "./CommentConversation.vue";
import type { CommentsPanelState, CommentUiConfig } from "./types";

/**
 * The floating conversation beside a pin: the reference strip is the title
 * bar, the thread scrolls inside and the composer stays at the bottom.
 */
const {
  state,
  ui,
  draftStorageKey = null,
  surfaceLabel = null,
  currentUserId = null,
} = defineProps<{
  state: CommentsPanelState;
  ui: CommentUiConfig;
  draftStorageKey?: string | null;
  surfaceLabel?: string | null;
  currentUserId?: number | null;
}>();
const live = useLive();
const emit = defineEmits<{ close: [] }>();
function close() {
  emit("close");
  live.pushEvent("comments_close", {});
}
</script>

<template>
  <section
    class="flex max-h-full min-h-0 flex-col overflow-hidden rounded-xl border border-border bg-popover text-popover-foreground shadow-xl"
    :aria-label="$t(`${ui.i18nPrefix}.${state.thread ? 'title' : 'new_thread'}`)"
  >
    <CommentConversation
      :state="state"
      :ui="ui"
      :draft-storage-key="draftStorageKey"
      :surface-label="surfaceLabel"
      :current-user-id="currentUserId"
      show-close
      @close="close"
    />
    <slot name="footer" />
  </section>
</template>
