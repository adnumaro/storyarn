<script setup lang="ts">
import CommentComposer from "@components/comments/CommentComposer.vue";
import type { CommentMember, FlowCommentPosition } from "../../../../types/comments";
import { flowCommentUi } from "../../../lib/flowCommentUi";

const {
  nodeId,
  threadId = null,
  parentId = null,
  position = null,
  draftId = null,
  members,
  disabled = false,
} = defineProps<{
  nodeId: number | null;
  threadId?: number | null;
  parentId?: number | null;
  position?: FlowCommentPosition | null;
  draftId?: string | null;
  members: CommentMember[];
  disabled?: boolean;
}>();

const emit = defineEmits<{ sent: [] }>();
</script>

<template>
  <CommentComposer
    :source-id="nodeId"
    :thread-id="threadId"
    :parent-id="parentId"
    :position="position"
    :draft-id="draftId"
    :members="members"
    :disabled="disabled"
    :ui="flowCommentUi"
    @sent="emit('sent')"
  />
</template>
