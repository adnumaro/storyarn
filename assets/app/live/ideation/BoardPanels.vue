<script setup lang="ts">
import ReferencesPanel from "./ReferencesPanel.vue";
import DecisionsPanel from "./DecisionsPanel.vue";
import type { ReferencesPanelState } from "./referenceTypes";
import type { DecisionsPanelState } from "./decisionTypes";

defineProps<{
  references: ReferencesPanelState;
  decisions?: DecisionsPanelState;
  epoch: string;
  sessionId: number;
}>();
</script>

<template>
  <!-- LiveVue accepts one injector per target slot. Compose both panels inside
       that boundary so a closed panel cannot overwrite the visible one. -->
  <div class="contents">
    <ReferencesPanel :state="references" :epoch="epoch" :session-id="sessionId" />
    <DecisionsPanel v-if="decisions" :state="decisions" :epoch="epoch" :session-id="sessionId" />
  </div>
</template>
