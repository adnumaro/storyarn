<script setup lang="ts">
import { computed } from "vue";
import CommentPopover from "@components/comments/CommentPopover.vue";
import type { FlowCommentsPanelState } from "../../../types/comments";
import { adaptFlowCommentsState, flowCommentUi } from "../../lib/flowCommentUi";

const { state, draftStorageKey = null } = defineProps<{
  state: FlowCommentsPanelState;
  draftStorageKey?: string | null;
}>();

const sharedState = computed(() => adaptFlowCommentsState(state));
</script>

<template>
  <CommentPopover :state="sharedState" :ui="flowCommentUi" :draft-storage-key="draftStorageKey" />
</template>
