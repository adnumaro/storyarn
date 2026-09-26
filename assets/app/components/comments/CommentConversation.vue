<script setup lang="ts">
import { Bell, BellOff, CheckCheck, CircleAlert, Lock, RotateCcw } from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import CommentComposer from "./CommentComposer.vue";
import CommentMessageItem from "./CommentMessageItem.vue";
import CommentThreadHeader from "./CommentThreadHeader.vue";
import { formatRelativeTime } from "@shared/utils/date-utils";
import type { CommentMessage, CommentsPanelState, CommentThread, CommentUiConfig } from "./types";
import { currentPagePermalink, useCommentThreadActions } from "./useCommentThreadActions";

interface StoredReplyTarget {
  parentId: number;
  threadId: number;
  sourceId: number;
  sourceType: string;
}

/**
 * The body of a conversation, shared by the editor popover, the Sequence
 * dialog and the hub detail: reference header, thread, footer and composer.
 */
const {
  state,
  ui,
  draftStorageKey = null,
  surfaceLabel = null,
  permalink = null,
  currentUserId = null,
  showHeader = true,
  headerVariant = "strip",
  showClose = false,
  messagesId = null,
} = defineProps<{
  state: CommentsPanelState;
  ui: CommentUiConfig;
  draftStorageKey?: string | null;
  /** Name of the surface (sheet, flow, scene, session) for drafts, which have no thread yet. */
  surfaceLabel?: string | null;
  /** Deep link to the thread when the current page is not its editor (the hub). */
  permalink?: string | null;
  currentUserId?: number | null;
  showHeader?: boolean;
  headerVariant?: "strip" | "card";
  showClose?: boolean;
  /** Optional id for the scrolling message list, so a host can remember its position. */
  messagesId?: string | null;
}>();
const emit = defineEmits<{ close: [] }>();
const live = useLive();
const { locale } = useI18n();
const replyToId = ref<number | null>(readReplyTarget());
const translationKey = (name: string) => `${ui.i18nPrefix}.${name}`;
const thread = computed(() => state.thread);
const sourceAvailable = computed(() => !state.thread || state.thread.source.status === "available");
const composerEnabled = computed(
  () =>
    state.canComment &&
    sourceAvailable.value &&
    (state.thread
      ? state.thread.status === "open"
      : state.selectedSourceId != null || state.draftPosition != null),
);
const rootMessage = computed(
  () => state.messages.find((message) => message.parent_id == null) ?? state.messages[0],
);
const replyParentId = computed(
  () => replyToId.value ?? state.thread?.root_message_id ?? rootMessage.value?.id ?? null,
);
const replyTarget = computed(() =>
  state.messages.find((message) => message.id === replyToId.value && message.parent_id != null),
);
const currentUser = computed(() => state.members.find((member) => member.id === currentUserId));
const permalinkFor = () =>
  permalink ?? (thread.value ? currentPagePermalink(thread.value.id) : null);
const actions = useCommentThreadActions(() => state, ui, permalinkFor);
const resolvedLine = computed(() => {
  const current = thread.value;
  if (!current || current.status !== "resolved" || !current.resolved_by || !current.resolved_at)
    return null;
  return {
    name: current.resolved_by.display_name,
    time: formatRelativeTime(current.resolved_at, locale.value),
  };
});

watch(
  [
    () => state.thread?.id,
    () => state.thread?.source.id,
    () => state.thread?.source.type,
    () => draftStorageKey,
  ],
  () => {
    replyToId.value = readReplyTarget();
  },
  { flush: "sync" },
);

function replyTargetKey() {
  return ui.persistReplyDraft && draftStorageKey && state.thread
    ? `${draftStorageKey}:reply-target`
    : null;
}

function readReplyTarget(): number | null {
  const key = replyTargetKey();
  const current = state.thread;
  if (!key || !current || typeof window === "undefined") return null;
  try {
    const stored: unknown = JSON.parse(window.sessionStorage.getItem(key) ?? "null");
    return validReplyTarget(stored, current) ? stored.parentId : null;
  } catch {
    // A malformed or unavailable session draft must not change the reply target.
  }
  return null;
}

function validReplyTarget(value: unknown, current: CommentThread): value is StoredReplyTarget {
  if (!value || typeof value !== "object") return false;
  const candidate = value as StoredReplyTarget;
  return (
    typeof candidate.parentId === "number" &&
    Number.isSafeInteger(candidate.parentId) &&
    candidate.parentId > 0 &&
    candidate.threadId === current.id &&
    candidate.sourceId === current.source.id &&
    candidate.sourceType === current.source.type
  );
}

function selectReply(message: CommentMessage | null) {
  const parentId = message && message.parent_id != null ? message.id : null;
  replyToId.value = parentId;
  const key = replyTargetKey();
  const current = state.thread;
  if (!key || !current || typeof window === "undefined") return;
  try {
    if (parentId == null) window.sessionStorage.removeItem(key);
    else
      window.sessionStorage.setItem(
        key,
        JSON.stringify({
          parentId,
          threadId: current.id,
          sourceId: current.source.id,
          sourceType: current.source.type,
        }),
      );
  } catch {
    // Replying remains available when browser storage is disabled.
  }
}
</script>

<template>
  <div :id="`${ui.domScope}-comments-content`" class="flex min-h-0 flex-1 flex-col">
    <CommentThreadHeader
      v-if="showHeader"
      class="shrink-0"
      :state="state"
      :ui="ui"
      :actions="actions"
      :surface-label="surfaceLabel"
      :variant="headerVariant"
      :show-close="showClose"
      @close="emit('close')"
    />
    <p
      v-if="state.error || (!showHeader && actions.error.value)"
      role="alert"
      class="mx-3.5 mt-2 shrink-0 rounded-md bg-destructive/10 p-2 text-xs text-destructive"
    >
      {{ state.error || actions.error.value }}
    </p>

    <div
      v-if="thread"
      :id="messagesId ?? undefined"
      class="min-h-0 flex-1 overflow-y-auto overscroll-contain py-1.5"
    >
      <p
        v-if="!sourceAvailable"
        role="status"
        class="mx-3.5 mb-2 flex gap-2 rounded-md border border-[hsl(24_85%_60%/.3)] bg-[hsl(24_85%_60%/.08)] px-2.5 py-2 text-xs leading-relaxed"
      >
        <CircleAlert class="mt-0.5 size-3.5 shrink-0 text-[hsl(24_85%_62%)]" />
        {{
          $t(
            translationKey(
              thread.source.type === ui.canvasSourceType ? "canvas_unavailable" : "unavailable",
            ),
          )
        }}
      </p>
      <Button
        v-if="state.messageNextCursor"
        variant="ghost"
        size="xs"
        class="mx-3.5 mb-1 w-[calc(100%-1.75rem)] text-muted-foreground"
        @click="live.pushEvent('comments_load_messages', {})"
        >{{ $t(translationKey("load_messages")) }}</Button
      >
      <ol aria-live="polite" :aria-label="$t(translationKey('messages'))">
        <li v-for="message in state.messages" :key="message.id">
          <CommentMessageItem
            :message="message"
            :ui="ui"
            :root="message.id === rootMessage?.id"
            :mine="message.author.id != null && message.author.id === currentUserId"
            :highlighted="replyToId === message.id"
            :can-reply="composerEnabled && message.id !== rootMessage?.id"
            @reply="selectReply"
          />
        </li>
      </ol>
    </div>

    <div
      v-if="state.canComment && sourceAvailable"
      v-show="composerEnabled"
      class="shrink-0 px-3.5 py-2.5"
      :class="{ 'border-t border-border': thread }"
    >
      <CommentComposer
        :source-id="state.selectedSourceId"
        :position="state.draftPosition ?? null"
        :context="state.draftContext"
        :storage="{ draftId: state.draftId ?? null, key: draftStorageKey }"
        :thread-id="state.thread?.id ?? null"
        :parent-id="replyParentId"
        :members="state.members"
        :disabled="!composerEnabled || Boolean(state.draftPending)"
        :ui="ui"
        :answering="{
          to: replyTarget?.author ?? null,
          previous: replyToId != null && !replyTarget,
          authorName: currentUser?.display_name ?? null,
        }"
        @sent="selectReply(null)"
        @cancel-reply="selectReply(null)"
      />
    </div>
    <div
      v-if="thread?.status === 'resolved' && sourceAvailable"
      class="flex shrink-0 items-center gap-2 border-t border-border py-2 pl-3.5 pr-2 text-xs"
    >
      <CheckCheck class="size-3.5 shrink-0 text-[hsl(150_45%_55%)]" />
      <span class="min-w-0 flex-1 text-muted-foreground">
        <i18n-t v-if="resolvedLine" :keypath="translationKey('resolved_by')" tag="span">
          <template #name
            ><span class="text-foreground">{{ resolvedLine.name }}</span></template
          >
          <template #time>{{ resolvedLine.time }}</template>
        </i18n-t>
        <template v-else>{{ $t(translationKey("resolved_hint")) }}</template>
      </span>
      <Button
        v-if="actions.canChangeStatus.value"
        :id="`${ui.domScope}-comment-reopen`"
        variant="outline"
        size="xs"
        :disabled="actions.pending.value"
        @click="actions.setStatus('open')"
        ><RotateCcw class="size-3" />{{ $t(translationKey("reopen")) }}</Button
      >
    </div>
    <div
      v-else-if="thread && !state.canComment"
      class="flex shrink-0 items-center gap-2 border-t border-border py-2 pl-3.5 pr-2 text-xs text-muted-foreground"
    >
      <Lock class="size-3.5 shrink-0" />
      <span class="min-w-0 flex-1">{{ $t(translationKey("viewer_hint")) }}</span>
      <Button
        v-if="sourceAvailable && thread.unread"
        :id="`${ui.domScope}-comment-read-toggle`"
        variant="ghost"
        size="xs"
        :disabled="actions.pending.value"
        @click="actions.markRead()"
        ><CheckCheck class="size-3" />{{ $t(translationKey("mark_read")) }}</Button
      >
      <Button
        v-if="sourceAvailable"
        :id="`${ui.domScope}-comment-follow-toggle`"
        variant="ghost"
        size="xs"
        :disabled="actions.pending.value"
        @click="actions.toggleFollow()"
        ><BellOff v-if="thread.following" class="size-3" /><Bell v-else class="size-3" />{{
          $t(translationKey(thread.following ? "unfollow" : "follow"))
        }}</Button
      >
    </div>
  </div>
</template>
