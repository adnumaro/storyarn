<script setup lang="ts">
import { computed, onUnmounted, watch } from "vue";
import CommentDialog from "@components/comments/CommentDialog.vue";
import { useLive } from "@shared/composables/useLive";
import type { FlowCommentsPanelState } from "@modules/flows/types/comments";
import { adaptFlowCommentsState, flowCommentUi } from "../../lib/flowCommentUi";

const { nodeId, state } = defineProps<{
  nodeId: string | number | null;
  state: FlowCommentsPanelState;
}>();
const live = useLive();
const ui = { ...flowCommentUi, domScope: "sequence" };
const open = computed(
  () =>
    state.open &&
    state.presentation === "workspace" &&
    String(state.selectedNodeId) === String(nodeId),
);
const sharedState = computed(() => adaptFlowCommentsState(state));
function show() {
  if (nodeId != null)
    live.pushEvent("comments_open", { node_id: nodeId, presentation: "workspace" });
}
function close() {
  live.pushEvent("comments_close", {});
}
watch(
  () => nodeId,
  (next, previous) => {
    if (
      state.open &&
      state.presentation === "workspace" &&
      String(state.selectedNodeId) === String(previous)
    ) {
      if (next == null) close();
      else show();
    }
  },
);
onUnmounted(() => {
  if (state.open && state.presentation === "workspace") close();
});
</script>

<template>
  <CommentDialog
    :state="{ ...sharedState, open }"
    :ui="ui"
    :draft-storage-key="`sequence-comments-${nodeId}`"
  />
</template>
