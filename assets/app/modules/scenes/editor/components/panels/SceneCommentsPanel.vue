<script setup lang="ts">
import { computed } from "vue";
import CommentsPanel from "@components/comments/CommentsPanel.vue";
import type { SceneCommentsPanelState } from "../../../types/comments";
import { adaptSceneCommentsState, sceneCommentUi } from "../../lib/sceneCommentUi";

const { state, embedded = false } = defineProps<{
  state: SceneCommentsPanelState;
  embedded?: boolean;
}>();

const sharedState = computed(() => adaptSceneCommentsState(state));
</script>

<template>
  <CommentsPanel :state="sharedState" :ui="sceneCommentUi" :embedded="embedded" />
</template>
