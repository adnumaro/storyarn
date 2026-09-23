<script setup lang="ts">
import ReferencesPanel from "./ReferencesPanel.vue";
import DecisionsPanel from "./DecisionsPanel.vue";
import SessionPanel from "./SessionPanel.vue";
import type { ReferencesPanelState } from "./referenceTypes";
import type { DecisionsPanelState } from "./decisionTypes";
import type { Member, Session } from "@modules/ideation";
import type { DecisionDiscussionState } from "./decisionTypes";

// Injected into the layout's dock from the first render: the dock only picks
// up injectors that exist when it mounts, so a session opened from the list
// (a live patch, not a page load) keeps its panels. LiveVue accepts one
// injector per target slot; every panel composes inside this boundary.
const {
  session = null,
  members = [],
  canManage = false,
  sessionPanel = false,
  discussion = { state: null, counts: {} },
} = defineProps<{
  references: ReferencesPanelState;
  decisions?: DecisionsPanelState;
  discussion?: DecisionDiscussionState;
  epoch: string;
  sessionId: number | null;
  session?: Session | null;
  members?: Member[];
  canManage?: boolean;
  sessionPanel?: boolean;
}>();
</script>

<template>
  <div v-if="sessionId !== null" class="contents">
    <ReferencesPanel :state="references" :epoch="epoch" :session-id="sessionId" />
    <DecisionsPanel
      v-if="decisions"
      :state="decisions"
      :epoch="epoch"
      :session-id="sessionId"
      :discussion="discussion"
    />
    <SessionPanel
      v-if="session"
      :key="session.id"
      :open="sessionPanel"
      :session="session"
      :epoch="epoch"
      :members="members"
      :can-manage="canManage"
    />
  </div>
</template>
