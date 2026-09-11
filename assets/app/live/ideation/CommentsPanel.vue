<script setup lang="ts">
import { computed, provide, ref, watch } from "vue";
import { Bell, BellOff, CheckCheck } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { useI18n } from "vue-i18n";
import CommentsPanel from "@components/comments/CommentsPanel.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import type { CommentsPanelState, CommentUiConfig } from "@components/comments/types";
import { useLive, type LiveInterface } from "@shared/composables/useLive";

interface State extends CommentsPanelState {
  ideaId: number | null;
  groupId?: number | null;
  context: string;
}
const { state, epoch, sessionId, baseUrl } = defineProps<{
  state: State;
  epoch: string;
  sessionId: number;
  baseUrl: string;
}>();
const live = useLive();
const { t } = useI18n();
const message = (code: unknown) =>
  t(`brainstormingComments.${code === "stale" ? "stale" : "unavailable"}`);
const sourceLabel = computed(() => {
  if (state.groupId) return t("brainstormingComments.group_label");
  if (state.ideaId) return t("brainstormingComments.idea_label");
  return t("brainstormingComments.canvas_label");
});
const panel = computed(() => ({
  ...state,
  selectedSourceLabel: sourceLabel.value,
  error: state.error ? message(state.error) : null,
}));
const ui: CommentUiConfig = {
  domScope: "brainstorming",
  i18nPrefix: "brainstormingComments",
  canvasSourceType: "ideation_session",
  scopeThreadsKey: "session_threads",
  selectedSourceFallbackKey: "idea_label",
  createSourceKey: "idea_id",
  mentionsEnabled: true,
};
// Shared components keep their ordinary event contract; this boundary binds
// every request to the board generation and the selected discussion context.
provide<LiveInterface>("_live_vue", {
  ...live,
  pushEvent(event, payload, callback, onError) {
    live.pushEvent(
      event,
      {
        ...payload,
        epoch,
        session_id: sessionId,
        comment_context: state.context,
        ...(event === "comments_open"
          ? { idea_id: state.ideaId, group_id: state.groupId ?? null }
          : {}),
      },
      (reply) =>
        callback?.(reply?.ok === false ? { ...reply, error: message(reply.error) } : reply),
      onError,
    );
  },
});
const pending = ref(false);
const actionError = ref<string | null>(null);
let requestToken: symbol | null = null;
watch(
  () => `${epoch}:${sessionId}:${state.context}:${state.thread?.id}:${state.open}`,
  () => {
    requestToken = null;
    pending.value = false;
    actionError.value = null;
  },
);
function personalAction(action: "follow" | "read") {
  const thread = state.thread;
  if (!thread || pending.value) return;
  const token = Symbol();
  requestToken = token;
  pending.value = true;
  actionError.value = null;
  const finish = (ok: boolean) => {
    if (requestToken !== token) return;
    pending.value = false;
    requestToken = null;
    if (!ok) actionError.value = t("brainstormingComments.update_failed");
  };
  live.pushEvent(
    `comments_${action}`,
    {
      epoch,
      session_id: sessionId,
      comment_context: state.context,
      thread_id: thread.id,
      ...(action === "follow"
        ? { following: !thread.following }
        : { message_id: thread.last_message_id }),
    },
    (reply) => finish(reply.ok === true),
    () => finish(false),
  );
}
</script>

<template>
  <CommentsPanel
    v-if="state.open"
    :key="`${epoch}:${sessionId}:${state.context}`"
    :state="panel"
    :ui="ui"
  >
    <template v-if="state.thread" #footer>
      <div class="space-y-2 px-3 py-2">
        <div class="flex flex-wrap items-center gap-2">
          <Button
            id="brainstorming-comment-follow"
            variant="outline"
            size="sm"
            :disabled="pending"
            :aria-pressed="state.thread.following"
            @click="personalAction('follow')"
          >
            <BellOff v-if="state.thread.following" class="size-4" /><Bell v-else class="size-4" />
            {{
              t(
                state.thread.following
                  ? "brainstormingComments.unfollow"
                  : "brainstormingComments.follow",
              )
            }}
          </Button>
          <Button
            v-if="state.thread.unread"
            id="brainstorming-comment-read"
            variant="ghost"
            size="sm"
            :disabled="pending"
            @click="personalAction('read')"
            ><CheckCheck class="size-4" />{{ t("brainstormingComments.mark_read") }}</Button
          >
        </div>
        <p class="text-xs text-muted-foreground">{{ t("brainstormingComments.follow_help") }}</p>
        <p v-if="actionError" role="alert" class="text-xs text-destructive">{{ actionError }}</p>
      </div>
      <LiveLink
        :to="`${baseUrl}/${sessionId}?thread=${state.thread.id}`"
        mode="patch"
        class="block px-3 py-2 text-xs text-muted-foreground hover:text-foreground"
        id="brainstorming-comment-link"
        >{{ $t("brainstormingComments.permalink") }}</LiveLink
      >
    </template>
  </CommentsPanel>
</template>
