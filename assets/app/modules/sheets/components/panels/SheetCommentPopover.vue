<script setup lang="ts">
import { computed } from "vue";
import CommentPopover from "@components/comments/CommentPopover.vue";
import { adaptSheetCommentsState, sheetCommentUi } from "../../lib/sheetCommentUi";
import type { SheetCommentsPanelState } from "../../types/comments";

const { state, draftStorageKey = null } = defineProps<{
  state: SheetCommentsPanelState;
  draftStorageKey?: string | null;
}>();

const sharedState = computed(() => adaptSheetCommentsState(state));
</script>

<template>
  <CommentPopover :state="sharedState" :ui="sheetCommentUi" :draft-storage-key="draftStorageKey" />
</template>
