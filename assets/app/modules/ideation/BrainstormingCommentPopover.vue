<script setup lang="ts">
import { computed, provide } from "vue";
import { useI18n } from "vue-i18n";
import CommentPopover from "@components/comments/CommentPopover.vue";
import type { CommentUiConfig } from "@components/comments/types";
import { useLive, type LiveInterface } from "@shared/composables/useLive";
import type { BrainstormingCommentsState } from "./commentTypes";

const {
  state,
  epoch,
  sessionId,
  baseUrl,
  currentUserId = null,
} = defineProps<{
  state: BrainstormingCommentsState;
  epoch: string;
  sessionId: number;
  baseUrl: string;
  currentUserId?: number | null;
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
const permalink = computed(() =>
  state.thread && typeof window !== "undefined"
    ? new URL(
        `${baseUrl}/${sessionId}?thread=${state.thread.id}`,
        window.location.origin,
      ).toString()
    : null,
);
const ui: CommentUiConfig = {
  domScope: "brainstorming",
  i18nPrefix: "brainstormingComments",
  canvasSourceType: "ideation_session",
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
        callback?.(
          reply?.ok === false && !event.startsWith("comments_follow") && event !== "comments_read"
            ? { ...reply, error: message(reply.error) }
            : reply,
        ),
      onError,
    );
  },
});
</script>

<template>
  <CommentPopover
    v-if="state.open"
    :key="`${epoch}:${sessionId}:${state.context}`"
    :state="panel"
    :ui="ui"
    :permalink="permalink"
    :current-user-id="currentUserId"
  />
</template>
