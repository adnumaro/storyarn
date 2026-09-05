<script setup lang="ts">
import { computed } from "vue";
import CommentsPanel from "@components/comments/CommentsPanel.vue";
import { adaptSheetCommentsState, sheetCommentUi } from "../../lib/sheetCommentUi";
import type { SheetCommentsPanelState } from "../../types/comments";

const { state, embedded = false } = defineProps<{
  state: SheetCommentsPanelState;
  embedded?: boolean;
}>();

const sharedState = computed(() => adaptSheetCommentsState(state));
</script>

<template>
  <CommentsPanel :state="sharedState" :ui="sheetCommentUi" :embedded="embedded" />
</template>
