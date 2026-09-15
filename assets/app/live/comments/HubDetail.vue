<script setup lang="ts">
import { ArrowLeft, ArrowUpRight, ChevronRight, CircleAlert, MessagesSquare } from "@lucide/vue";
import { computed } from "vue";
import CommentConversation from "@components/comments/CommentConversation.vue";
import { commentTool, commentToolKey } from "@components/comments/commentTool";
import type { CommentUiConfig } from "@components/comments/types";
import LiveLink from "@components/navigation/LiveLink.vue";
import { Button } from "@components/ui/button";
import type { HubState, HubThread } from "./types";

/** The selected conversation: where it lives, the reference card, the thread and the composer. */
const {
  state,
  selected = null,
  currentUserId,
  draftStorageKey = null,
  detailVisible = false,
} = defineProps<{
  state: HubState;
  selected?: HubThread | null;
  currentUserId: number;
  draftStorageKey?: string | null;
  /** A selection exists (even if it could not be loaded), so mobile shows this pane. */
  detailVisible?: boolean;
}>();
const emit = defineEmits<{ back: [] }>();
const ui: CommentUiConfig = {
  persistReplyDraft: true,
  domScope: "hub",
  i18nPrefix: "comments_hub",
  canvasSourceType: "__hub_source_label__",
  selectedSourceFallbackKey: "source_label",
};
const conversation = computed(() => state.conversation.thread);
const projectName = computed(
  () =>
    selected?.project_name ??
    state.projects.find((project) => project.id === state.selectedProjectId)?.name ??
    "",
);
const tool = computed(() =>
  conversation.value ? commentTool(conversation.value.source.type) : null,
);
const toolKey = computed(() =>
  conversation.value ? commentToolKey(conversation.value.source.type) : null,
);
const permalink = computed(() =>
  state.contextUrl && typeof window !== "undefined"
    ? new URL(state.contextUrl, window.location.origin).toString()
    : null,
);
</script>

<template>
  <div class="flex min-h-0 min-w-0 flex-1 flex-col">
    <template v-if="conversation && tool">
      <div
        class="flex min-h-12 shrink-0 items-center gap-2 border-b border-border px-3 py-2 sm:px-5"
      >
        <Button
          id="comments-hub-back"
          variant="ghost"
          size="icon-sm"
          class="-ml-2 shrink-0 md:hidden"
          :aria-label="$t('comments_hub.all_threads')"
          @click="emit('back')"
          ><ArrowLeft class="size-4"
        /></Button>
        <div
          class="flex min-w-0 flex-1 items-center gap-1.5 whitespace-nowrap text-xs text-muted-foreground"
        >
          <span class="truncate font-medium text-foreground">{{ projectName }}</span>
          <ChevronRight class="size-3 shrink-0" />
          <component :is="tool.icon" class="size-3 shrink-0" :class="tool.colorClass" />
          <span class="shrink-0">{{ $t(`comments_hub.tools.${toolKey}`) }}</span>
          <template v-if="selected?.workspace_name">
            <span aria-hidden="true">·</span>
            <span class="truncate">{{ selected.workspace_name }}</span>
          </template>
        </div>
        <LiveLink
          v-if="state.contextUrl && conversation.source.status === 'available'"
          id="comments-hub-context"
          :to="state.contextUrl"
          class="inline-flex h-8 shrink-0 items-center gap-1.5 rounded-md border border-input bg-background px-3 text-xs font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring dark:bg-input/30"
          >{{ $t("comments_hub.open_in_editor") }}<ArrowUpRight class="size-3.5"
        /></LiveLink>
      </div>
      <div class="flex min-h-0 flex-1 flex-col px-1 pt-3 sm:px-3">
        <CommentConversation
          :key="`${currentUserId}:${state.selectedProjectId}:${state.selectedThreadId}`"
          :state="state.conversation"
          :ui="ui"
          :draft-storage-key="draftStorageKey"
          :permalink="permalink"
          :current-user-id="currentUserId"
          header-variant="card"
          messages-id="comments-hub-detail"
          class="[&>div:first-child]:mx-2.5"
        />
      </div>
    </template>
    <div
      v-else
      class="flex min-h-0 flex-1 flex-col items-center justify-center gap-2.5 px-8 py-16 text-center"
    >
      <div
        class="flex size-11 items-center justify-center rounded-xl"
        :class="
          detailVisible
            ? 'bg-[hsl(24_85%_60%/.12)] text-[hsl(24_85%_62%)]'
            : 'bg-muted text-muted-foreground'
        "
      >
        <CircleAlert v-if="detailVisible" class="size-5" />
        <MessagesSquare v-else class="size-5" />
      </div>
      <h2 class="text-[15px] font-semibold">
        {{ $t(detailVisible ? "comments_hub.unavailable_title" : "comments_hub.select_thread") }}
      </h2>
      <p class="max-w-xs text-[13px] leading-relaxed text-muted-foreground">
        {{
          $t(detailVisible ? "comments_hub.unavailable_detail" : "comments_hub.select_thread_hint")
        }}
      </p>
      <Button
        v-if="detailVisible"
        variant="outline"
        size="sm"
        class="mt-1 gap-1.5"
        @click="emit('back')"
        ><ArrowLeft class="size-3.5" />{{ $t("comments_hub.all_threads") }}</Button
      >
    </div>
  </div>
</template>
