<script setup lang="ts">
import CommentsPanel from "./CommentsPanel.vue";
import ReferencesPanel from "./ReferencesPanel.vue";
import DecisionsPanel from "./DecisionsPanel.vue";
import type { BrainstormingCommentsState } from "./commentTypes";
import type { ReferencesPanelState } from "./referenceTypes";
import type { DecisionsPanelState } from "./decisionTypes";

defineProps<{
  comments: BrainstormingCommentsState;
  references: ReferencesPanelState;
  decisions?: DecisionsPanelState;
  epoch: string;
  sessionId: number;
  baseUrl: string;
}>();
</script>

<template>
  <!-- LiveVue accepts one injector per target slot. Compose both panels inside
       that boundary so a closed panel cannot overwrite the visible one. -->
  <div class="contents">
    <CommentsPanel :state="comments" :epoch="epoch" :session-id="sessionId" :base-url="baseUrl" />
    <ReferencesPanel :state="references" :epoch="epoch" :session-id="sessionId" />
    <DecisionsPanel v-if="decisions" :state="decisions" :epoch="epoch" :session-id="sessionId" />
  </div>
</template>
