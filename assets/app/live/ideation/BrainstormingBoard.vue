<script setup lang="ts">
import { BrainstormingWorkspace, type Board, type BoardLink } from "@modules/ideation";
import type { BrainstormingCommentsState } from "@modules/ideation/commentTypes";
defineProps<{
  board: Board;
  baseUrl: string;
  comments: BrainstormingCommentsState;
  linked?: BoardLink | null;
}>();
</script>
<template>
  <BrainstormingWorkspace
    :board="board"
    :comments="comments"
    :base-url="baseUrl"
    :linked="linked ?? null"
  />
</template>
