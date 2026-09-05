<script setup lang="ts">
import { computed } from "vue";
import CommentsPanel from "@components/comments/CommentsPanel.vue";
import type { FlowCommentsPanelState } from "../../../types/comments";
import { adaptFlowCommentsState, flowCommentUi } from "../../lib/flowCommentUi";

const { state, embedded = false } = defineProps<{
  state: FlowCommentsPanelState;
  embedded?: boolean;
}>();

const sharedState = computed(() => adaptFlowCommentsState(state));
</script>

<template>
  <CommentsPanel :state="sharedState" :ui="flowCommentUi" :embedded="embedded" />
</template>
