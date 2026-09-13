<script setup lang="ts">
import { BrainstormingWorkspace, type Board } from "@modules/ideation";
import type { BrainstormingCommentsState } from "@modules/ideation/commentTypes";
defineProps<{ board: Board; baseUrl: string; comments: BrainstormingCommentsState }>();
</script>
<template>
  <BrainstormingWorkspace :board="board" :comments="comments" :base-url="baseUrl" />
</template>
