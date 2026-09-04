<script setup lang="ts">
import { MessageCircle, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import Sidebar from "@app/shell/Sidebar.vue";
import FlowCommentConversation from "./comments/FlowCommentConversation.vue";
import type { FlowCommentsPanelState } from "../../../types/comments";

const { state, embedded = false } = defineProps<{
  state: FlowCommentsPanelState;
  embedded?: boolean;
}>();
const live = useLive();
</script>

<template>
  <section
    v-if="embedded"
    class="flex min-h-0 max-h-full flex-col overflow-hidden rounded-xl border border-border bg-background shadow-xl"
    :aria-label="$t('flows.comments.title')"
  >
    <div class="flex shrink-0 items-center justify-between gap-2 border-b border-border px-3 py-2">
      <div class="flex min-w-0 items-center gap-2 text-sm font-medium">
        <MessageCircle class="size-4 shrink-0 text-muted-foreground" />
        <span class="truncate">{{
          state.thread ? $t("flows.comments.title") : $t("flows.comments.new_thread")
        }}</span>
      </div>
      <Button
        id="flow-comment-popover-close"
        variant="ghost"
        size="icon"
        class="size-7"
        :aria-label="$t('flows.comments.close')"
        @click="live.pushEvent('comments_close', {})"
        ><X class="size-4"
      /></Button>
    </div>
    <FlowCommentConversation
      :state="state"
      embedded
      class="min-h-0 overflow-y-auto overscroll-contain p-3"
    />
  </section>
  <Sidebar
    v-else
    side="right"
    :open="state.open && state.presentation !== 'canvas'"
    @close="live.pushEvent('comments_close', {})"
  >
    <template #header>
      <div class="flex items-center justify-between gap-2 py-2.5">
        <div class="flex min-w-0 items-center gap-2 text-sm font-medium">
          <MessageCircle class="size-4 shrink-0" /><span>{{ $t("flows.comments.title") }}</span>
        </div>
        <Button
          id="flow-comments-close"
          variant="ghost"
          size="icon"
          class="size-7"
          :aria-label="$t('flows.comments.close')"
          @click="live.pushEvent('comments_close', {})"
          ><X class="size-4"
        /></Button>
      </div>
    </template>
    <FlowCommentConversation v-if="state.presentation !== 'canvas'" :state="state" />
  </Sidebar>
</template>
