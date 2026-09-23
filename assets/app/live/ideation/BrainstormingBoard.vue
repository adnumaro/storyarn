<script setup lang="ts">
import { BrainstormingWorkspace, type Board, type BoardLink } from "@modules/ideation";
import type { BrainstormingCommentsState } from "@modules/ideation/commentTypes";
import type { DecisionRecord } from "./decisionTypes";
defineProps<{
  board: Board;
  baseUrl: string;
  comments: BrainstormingCommentsState;
  linked?: BoardLink | null;
  decisionDraft?: boolean;
  decisions?: DecisionRecord[];
  decisionFocus?: number | null;
}>();
</script>
<template>
  <BrainstormingWorkspace
    :board="board"
    :comments="comments"
    :base-url="baseUrl"
    :linked="linked ?? null"
    :decision-draft="decisionDraft ?? false"
    :decisions="decisions ?? []"
    :decision-focus="decisionFocus ?? null"
  />
</template>
