<script setup lang="ts">
import { computed, onUnmounted, watch } from "vue";
import { MessageCircle, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import CommentConversation from "@components/comments/CommentConversation.vue";
import { useLive } from "@shared/composables/useLive";
import type { FlowCommentsPanelState } from "@modules/flows/types/comments";
import { adaptFlowCommentsState, flowCommentUi } from "../../lib/flowCommentUi";

const {
  nodeId,
  state,
  count = 0,
  top = 48,
} = defineProps<{
  nodeId: string | number | null;
  state: FlowCommentsPanelState;
  count?: number;
  top?: number;
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
  <Button
    variant="ghost"
    size="xs"
    :disabled="nodeId == null"
    :aria-expanded="open"
    aria-controls="sequence-comments"
    data-sequence-comments-toggle
    @click="open ? close() : show()"
  >
    <MessageCircle class="size-3.5" />{{ $t("flows.comments.title")
    }}<span v-if="count">{{ count }}</span>
  </Button>
  <aside
    v-if="open"
    id="sequence-comments"
    class="absolute right-2 bottom-2 z-30 flex w-80 max-w-[calc(100%-1rem)] flex-col rounded-lg border border-border bg-background shadow-xl"
    :style="{ top: `${top}px` }"
    :aria-label="$t('flows.comments.title')"
    @keydown.stop
    @keydown.esc.prevent="close"
    @pointerdown.stop
    @wheel.stop
  >
    <header class="flex shrink-0 items-center justify-between border-b border-border px-3 py-2">
      <span class="text-sm font-medium">{{ $t("flows.comments.title") }} · #{{ nodeId }}</span>
      <Button variant="ghost" size="icon-xs" :aria-label="$t('flows.comments.close')" @click="close"
        ><X class="size-4"
      /></Button>
    </header>
    <CommentConversation
      :key="String(nodeId)"
      :state="sharedState"
      :ui="ui"
      :draft-storage-key="`sequence-comments-${nodeId}`"
      class="min-h-0 overflow-y-auto overscroll-contain p-3"
    />
  </aside>
</template>
