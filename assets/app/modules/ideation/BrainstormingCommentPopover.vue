<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import CommentPopover from "@components/comments/CommentPopover.vue";
import type { CommentUiConfig } from "@components/comments/types";
import type { BrainstormingCommentsState } from "./commentTypes";
import { useCommentBridge } from "./composables/useCommentBridge";

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
const { t } = useI18n();
const { message } = useCommentBridge(
  () => state,
  () => ({ epoch, sessionId }),
);
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
