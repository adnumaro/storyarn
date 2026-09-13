<script setup lang="ts">
import { computed } from "vue";
import CommentPopover from "@components/comments/CommentPopover.vue";
import type { SceneCommentsPanelState } from "../../../types/comments";
import { adaptSceneCommentsState, sceneCommentUi } from "../../lib/sceneCommentUi";

const { state, draftStorageKey = null } = defineProps<{
  state: SceneCommentsPanelState;
  draftStorageKey?: string | null;
}>();

const emit = defineEmits<{ close: [] }>();
const sharedState = computed(() => adaptSceneCommentsState(state));
</script>

<template>
  <CommentPopover
    :state="sharedState"
    :ui="sceneCommentUi"
    :draft-storage-key="draftStorageKey"
    @close="emit('close')"
  />
</template>
