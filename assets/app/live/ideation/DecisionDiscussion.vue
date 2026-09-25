<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import CommentConversation from "@components/comments/CommentConversation.vue";
import type { CommentUiConfig } from "@components/comments/types";
import type { BrainstormingCommentsState } from "@modules/ideation/commentTypes";
import { useCommentBridge } from "@modules/ideation/composables/useCommentBridge";
import { sectionHeading } from "./decisionSections";

/**
 * The decision's conversation, inline in its detail. It is the board's comment
 * thread about the decision, so resolving it never accepts the decision and
 * accepting never resolves it.
 */
const {
  state,
  epoch,
  sessionId,
  title,
  currentUserId = null,
} = defineProps<{
  state: BrainstormingCommentsState;
  /** The decision's title names the conversation instead of its internal number. */
  title: string;
  epoch: string;
  sessionId: number;
  currentUserId?: number | null;
}>();
const { t } = useI18n();
const { message } = useCommentBridge(
  () => state,
  () => ({ epoch, sessionId }),
);
const panel = computed(() => ({
  ...state,
  thread: state.thread && {
    ...state.thread,
    source: { ...state.thread.source, label: title },
  },
  selectedSourceLabel: title,
  error: state.error ? message(state.error) : null,
}));
const ui: CommentUiConfig = {
  domScope: "decision-discussion",
  i18nPrefix: "brainstormingComments",
  canvasSourceType: "ideation_session",
  selectedSourceFallbackKey: "idea_label",
  createSourceKey: "decision_id",
  mentionsEnabled: true,
};
</script>
<template>
  <section id="decision-discussion" aria-labelledby="decision-discussion-title">
    <div class="mb-2.5 flex items-center gap-1.5 text-muted-foreground">
      <h3 id="decision-discussion-title" :class="sectionHeading">
        {{ t("brainstormingDecisions.discussion") }}
      </h3>
      <span v-if="state.thread" class="text-[11px]">· {{ state.thread.message_count }}</span>
      <span class="flex-1" />
      <span class="text-right text-[11px] text-pretty">{{
        t("brainstormingDecisions.discussionHint")
      }}</span>
    </div>
    <div class="-mx-3.5 -my-2.5 flex max-h-[420px] flex-col overflow-hidden">
      <CommentConversation
        :key="`${epoch}:${sessionId}:${state.context}`"
        :state="panel"
        :ui="ui"
        :current-user-id="currentUserId"
        :show-header="state.thread !== null"
      />
    </div>
  </section>
</template>
