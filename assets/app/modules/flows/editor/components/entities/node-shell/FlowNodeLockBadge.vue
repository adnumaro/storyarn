<script setup lang="ts">
import { Lock } from "@lucide/vue";
import type { FlowNodeLock } from "../../../services/editorHandlers";

const { lock, nodeId } = defineProps<{
  lock: FlowNodeLock;
  nodeId: string;
}>();
</script>

<template>
  <div
    class="pointer-events-none absolute -top-3 right-2 z-10 inline-flex max-w-40 items-center gap-1 rounded-full border bg-background px-1.5 py-0.5 text-[10px] font-medium shadow-sm"
    :style="{ color: lock.color, borderColor: lock.color }"
    role="status"
    :aria-label="$t('flows.node_lock.editing_by', { name: lock.name })"
    :data-flow-node-lock="nodeId"
  >
    <Lock class="size-3 shrink-0" aria-hidden="true" />
    <span class="truncate">{{ lock.name }}</span>
  </div>
</template>
