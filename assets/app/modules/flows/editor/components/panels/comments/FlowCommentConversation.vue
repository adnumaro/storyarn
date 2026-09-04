<script setup lang="ts">
import { computed } from "vue";
import CommentConversation from "@components/comments/CommentConversation.vue";
import type { FlowCommentsPanelState } from "../../../../types/comments";
import { adaptFlowCommentsState, flowCommentUi } from "../../../lib/flowCommentUi";

const { state, embedded = false } = defineProps<{
  state: FlowCommentsPanelState;
  embedded?: boolean;
}>();

const sharedState = computed(() => adaptFlowCommentsState(state));
</script>

<template>
  <CommentConversation :state="sharedState" :ui="flowCommentUi" :embedded="embedded" />
</template>
