<script setup lang="ts">
import { MessageCircle, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import CommentConversation from "./CommentConversation.vue";
import type { CommentsPanelState, CommentUiConfig } from "./types";

const {
  state,
  ui,
  draftStorageKey = null,
} = defineProps<{
  state: CommentsPanelState;
  ui: CommentUiConfig;
  draftStorageKey?: string | null;
}>();
const live = useLive();
const emit = defineEmits<{ close: [] }>();
function close() {
  emit("close");
  live.pushEvent("comments_close", {});
}
const translationKey = (name: string) => `${ui.i18nPrefix}.${name}`;
</script>

<template>
  <section
    class="flex min-h-0 max-h-full flex-col overflow-hidden rounded-xl border border-border bg-background shadow-xl"
    :aria-label="$t(translationKey('title'))"
  >
    <div class="flex shrink-0 items-center justify-between gap-2 border-b border-border px-3 py-2">
      <div class="flex min-w-0 items-center gap-2 text-sm font-medium">
        <MessageCircle class="size-4 shrink-0 text-muted-foreground" />
        <span class="truncate">{{
          state.thread ? $t(translationKey("title")) : $t(translationKey("new_thread"))
        }}</span>
      </div>
      <Button
        :id="`${ui.domScope}-comment-popover-close`"
        variant="ghost"
        size="icon"
        class="size-7"
        :aria-label="$t(translationKey('close'))"
        @click="close"
        ><X class="size-4"
      /></Button>
    </div>
    <CommentConversation
      :state="state"
      :ui="ui"
      :draft-storage-key="draftStorageKey"
      class="min-h-0 overflow-y-auto overscroll-contain p-3"
    />
    <slot name="footer" />
  </section>
</template>
