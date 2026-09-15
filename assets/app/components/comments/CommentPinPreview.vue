<script setup lang="ts">
import { computed } from "vue";
import { MessageCircle } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import UserAvatar from "@components/UserAvatar.vue";
import { commentContextIcon } from "./commentTool";
import { formatCommentTime } from "./commentTime";
import type { CommentThread, CommentUiConfig } from "./types";

/**
 * The card shown while hovering a pin: author, when, the root message and
 * where the thread is anchored, from the fields the thread already carries.
 */
const { thread, ui } = defineProps<{ thread: CommentThread; ui: CommentUiConfig }>();
const { locale } = useI18n();
const time = computed(() => formatCommentTime(thread.last_activity_at, locale.value));
const contextIcon = computed(() =>
  thread.context ? commentContextIcon(thread.context.type, thread.context.preview?.kind) : null,
);
</script>

<template>
  <div
    class="rounded-xl border border-border bg-popover p-3 text-popover-foreground shadow-xl"
    role="tooltip"
  >
    <div class="flex items-center gap-2 text-xs">
      <UserAvatar :display-name="thread.author.display_name" size="xs" />
      <span class="truncate font-semibold">{{ thread.author.display_name }}</span>
      <span class="shrink-0 text-muted-foreground">{{ time }}</span>
    </div>
    <p class="mt-1.5 line-clamp-3 whitespace-pre-wrap break-words text-[13px] leading-relaxed">
      {{ thread.preview }}
    </p>
    <div class="mt-2 flex items-center gap-1.5 text-[11px] text-muted-foreground">
      <template v-if="thread.context">
        <component :is="contextIcon" class="size-[11px] shrink-0" />
        <span class="truncate">{{ thread.context.label }}</span>
        <span>·</span>
      </template>
      <MessageCircle class="size-[11px] shrink-0" />
      <span class="tabular-nums">{{
        $t(`${ui.i18nPrefix}.message_count`, { count: thread.message_count })
      }}</span>
    </div>
  </div>
</template>
