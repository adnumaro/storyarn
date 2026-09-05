<script setup lang="ts">
import { computed } from "vue";
import CommentsPanel from "@components/comments/CommentsPanel.vue";
import { adaptSheetCommentsState, sheetCommentUi } from "../../lib/sheetCommentUi";
import type { SheetCommentsPanelState } from "../../types/comments";

const {
  state,
  embedded = false,
  draftStorageKey = null,
} = defineProps<{
  state: SheetCommentsPanelState;
  embedded?: boolean;
  draftStorageKey?: string | null;
}>();

const sharedState = computed(() => adaptSheetCommentsState(state));
</script>

<template>
  <CommentsPanel
    :state="sharedState"
    :ui="sheetCommentUi"
    :embedded="embedded"
    :draft-storage-key="draftStorageKey"
  />
</template>
