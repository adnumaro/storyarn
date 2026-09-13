<script setup lang="ts">
import CommentDialog from "./CommentDialog.vue";
import ReferencesPanel from "./ReferencesPanel.vue";
import type { BrainstormingCommentsState } from "./commentTypes";
import type { ReferencesPanelState } from "./referenceTypes";

defineProps<{
  comments: BrainstormingCommentsState;
  references: ReferencesPanelState;
  epoch: string;
  sessionId: number;
  baseUrl: string;
}>();
</script>

<template>
  <!-- LiveVue accepts one injector per target slot. Compose the dialog and reference panel inside
       that boundary so a closed panel cannot overwrite the visible one. -->
  <div class="contents">
    <CommentDialog :state="comments" :epoch="epoch" :session-id="sessionId" :base-url="baseUrl" />
    <ReferencesPanel :state="references" :epoch="epoch" :session-id="sessionId" />
  </div>
</template>
