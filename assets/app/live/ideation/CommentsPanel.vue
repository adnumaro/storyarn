<script setup lang="ts">
import { computed, provide } from "vue";
import { useI18n } from "vue-i18n";
import CommentsPanel from "@components/comments/CommentsPanel.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import type { CommentsPanelState, CommentUiConfig } from "@components/comments/types";
import { useLive, type LiveInterface } from "@shared/composables/useLive";

interface State extends CommentsPanelState {
  ideaId: number | null;
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
const panel = computed(() => ({
  ...state,
  selectedSourceLabel: t(
    state.ideaId ? "brainstormingComments.idea_label" : "brainstormingComments.canvas_label",
  ),
  error: state.error ? message(state.error) : null,
}));
const ui: CommentUiConfig = {
  domScope: "brainstorming",
  i18nPrefix: "brainstormingComments",
  canvasSourceType: "ideation_session",
  scopeThreadsKey: "session_threads",
  selectedSourceFallbackKey: "idea_label",
  createSourceKey: "idea_id",
  mentionsEnabled: false,
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
        ...(event === "comments_open" ? { idea_id: state.ideaId } : {}),
      },
      (reply) =>
        callback?.(reply?.ok === false ? { ...reply, error: message(reply.error) } : reply),
      onError,
    );
  },
});
</script>

<template>
  <CommentsPanel
    v-if="state.open"
    :key="`${epoch}:${sessionId}:${state.context}`"
    :state="panel"
    :ui="ui"
  >
    <template v-if="state.thread" #footer>
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
