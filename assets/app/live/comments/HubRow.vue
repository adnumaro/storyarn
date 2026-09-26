<script setup lang="ts">
import {
  CheckCheck,
  ChevronRight,
  CircleAlert,
  LoaderCircle,
  MessageCircle,
  Unlink,
} from "@lucide/vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import UserAvatar from "@components/UserAvatar.vue";
import { commentContextIcon, commentTool } from "@components/comments/commentTool";
import { formatDate, formatRelativeTime } from "@shared/utils/date-utils";
import type { HubThread } from "./types";

/** One conversation in the inbox list. */
const {
  thread,
  selected = false,
  busy = false,
} = defineProps<{
  thread: HubThread;
  selected?: boolean;
  busy?: boolean;
}>();
const emit = defineEmits<{ select: [thread: HubThread] }>();
const { locale } = useI18n();
const tool = computed(() => commentTool(thread.source.type));
const title = computed(() => (thread.preview || "").split("\n")[0]);
const last = computed(() => thread.last_message ?? null);
const time = computed(() => formatRelativeTime(thread.last_activity_at, locale.value));
const fullTime = computed(() => formatDate(thread.last_activity_at, locale.value, "datetime"));
const contextIcon = computed(() =>
  thread.context ? commentContextIcon(thread.context.type, thread.context.preview?.kind) : null,
);
</script>

<template>
  <button
    :id="`comments-hub-thread-${thread.id}`"
    type="button"
    :aria-pressed="selected"
    :aria-busy="busy"
    class="group relative flex w-full gap-2.5 py-2.5 pl-3.5 pr-4 text-left outline-none transition-colors hover:bg-muted/50 focus-visible:z-10 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
    :class="
      selected
        ? 'bg-accent/60 after:absolute after:inset-y-0 after:left-0 after:w-0.5 after:bg-primary'
        : ''
    "
    @click="emit('select', thread)"
  >
    <div class="flex w-6 shrink-0 flex-col items-center gap-2 pt-0.5">
      <component :is="tool.icon" class="size-4" :class="tool.colorClass" />
      <span
        v-if="thread.unread"
        class="size-[7px] rounded-full bg-primary"
        :aria-label="$t('comments_hub.unread')"
      />
    </div>
    <div class="min-w-0 flex-1">
      <div class="flex items-baseline gap-2">
        <span
          class="min-w-0 flex-1 truncate text-[13px]"
          :class="thread.unread ? 'font-semibold' : 'font-medium'"
          >{{ title || $t("comments_hub.empty_preview") }}</span
        >
        <time
          :datetime="thread.last_activity_at"
          :title="fullTime"
          class="shrink-0 text-[11px] text-muted-foreground"
          >{{ time }}</time
        >
      </div>
      <div v-if="last" class="mt-1 flex items-center gap-1.5 text-xs text-muted-foreground">
        <UserAvatar :display-name="last.author.display_name" size="xs" class="shrink-0" />
        <span class="truncate">{{ last.body }}</span>
      </div>
      <div
        class="mt-1.5 flex items-center gap-1.5 whitespace-nowrap text-[11px] text-muted-foreground"
      >
        <span class="shrink-0">{{ thread.project_name }}</span>
        <ChevronRight class="size-2.5 shrink-0" />
        <span class="min-w-0 truncate">{{ thread.source.label }}</span>
        <template v-if="thread.context">
          <ChevronRight class="size-2.5 shrink-0" />
          <template v-if="thread.context.status === 'available'">
            <component :is="contextIcon" class="size-2.5 shrink-0" />
            <span class="min-w-0 truncate text-foreground">{{ thread.context.label }}</span>
          </template>
          <span v-else class="inline-flex items-center gap-1 text-[hsl(24_85%_62%)]"
            ><Unlink class="size-2.5" />{{ $t("comments_hub.context_removed") }}</span
          >
        </template>
        <span
          v-if="thread.source.status === 'unavailable'"
          class="inline-flex items-center gap-1 text-[hsl(24_85%_62%)]"
          ><CircleAlert class="size-2.5" />{{ $t("comments_hub.source_unavailable") }}</span
        >
        <span class="flex-1" />
        <span
          v-if="thread.message_count > 1"
          class="inline-flex shrink-0 items-center gap-1 tabular-nums"
          :aria-label="$t('comments_hub.message_count', { count: thread.message_count })"
          ><MessageCircle class="size-[11px]" />{{ thread.message_count }}</span
        >
        <CheckCheck
          v-if="thread.status === 'resolved'"
          class="size-3.5 shrink-0 text-[hsl(150_45%_55%)]"
          :aria-label="$t('comments_hub.resolved')"
        />
        <LoaderCircle v-if="busy" class="size-3.5 shrink-0 animate-spin" />
      </div>
    </div>
  </button>
</template>
