<script setup lang="ts">
import { computed } from "vue";
import CommentsPanel from "@components/comments/CommentsPanel.vue";
import type { FlowCommentsPanelState } from "../../../types/comments";
import { adaptFlowCommentsState, flowCommentUi } from "../../lib/flowCommentUi";

const {
  state,
  embedded = false,
  draftStorageKey = null,
} = defineProps<{
  state: FlowCommentsPanelState;
  embedded?: boolean;
  draftStorageKey?: string | null;
}>();

const sharedState = computed(() => adaptFlowCommentsState(state));
</script>

<template>
  <CommentsPanel
    :state="sharedState"
    :ui="flowCommentUi"
    :embedded="embedded"
    :draft-storage-key="draftStorageKey"
  />
</template>
