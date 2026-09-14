<script setup lang="ts">
import { computed } from "vue";
import CommentPopover from "@components/comments/CommentPopover.vue";
import type { SceneCommentsPanelState } from "../../../types/comments";
import { adaptSceneCommentsState, sceneCommentUi } from "../../lib/sceneCommentUi";

const {
  state,
  draftStorageKey = null,
  currentUserId = null,
} = defineProps<{
  state: SceneCommentsPanelState;
  draftStorageKey?: string | null;
  currentUserId?: number | null;
}>();

const emit = defineEmits<{ close: [] }>();
const sharedState = computed(() => adaptSceneCommentsState(state));
</script>

<template>
  <CommentPopover
    :state="sharedState"
    :ui="sceneCommentUi"
    :draft-storage-key="draftStorageKey"
    :current-user-id="currentUserId"
    @close="emit('close')"
  />
</template>
