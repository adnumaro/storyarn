<script setup lang="ts">
import { computed } from "vue";
import CommentsPanel from "@components/comments/CommentsPanel.vue";
import type { SceneCommentsPanelState } from "../../../types/comments";
import { adaptSceneCommentsState, sceneCommentUi } from "../../lib/sceneCommentUi";

const {
  state,
  embedded = false,
  draftStorageKey = null,
} = defineProps<{
  state: SceneCommentsPanelState;
  embedded?: boolean;
  draftStorageKey?: string | null;
}>();

const emit = defineEmits<{ close: [] }>();
const sharedState = computed(() => adaptSceneCommentsState(state));
</script>

<template>
  <CommentsPanel
    :state="sharedState"
    :ui="sceneCommentUi"
    :embedded="embedded"
    :draft-storage-key="draftStorageKey"
    @close="emit('close')"
  />
</template>
