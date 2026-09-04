<script setup lang="ts">
import { MessageCircle } from "@lucide/vue";
import { useLive } from "@shared/composables/useLive";

const {
  nodeId,
  count = 0,
  zoom = 1,
  revealed = true,
} = defineProps<{ nodeId: number | string; count?: number; zoom?: number; revealed?: boolean }>();
const live = useLive();
</script>

<template>
  <button
    :id="`flow-node-comments-${nodeId}`"
    type="button"
    class="absolute -right-2 -top-2 z-20 inline-flex h-6 min-w-6 items-center justify-center gap-1 rounded-full border border-border bg-background px-1.5 text-xs text-muted-foreground shadow-sm transition-colors hover:border-primary/50 hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
    :class="{
      'opacity-0 group-hover/comment-node:opacity-100 group-focus-within/comment-node:opacity-100 focus-visible:opacity-100':
        !count && !revealed,
    }"
    :style="{ transform: `scale(${1 / (zoom || 1)})`, transformOrigin: 'bottom left' }"
    :aria-label="
      count ? $t('flows.comments.node_count', { count }, count) : $t('flows.comments.new_thread')
    "
    :title="
      count ? $t('flows.comments.node_count', { count }, count) : $t('flows.comments.new_thread')
    "
    @pointerdown.stop
    @mousedown.stop
    @dblclick.stop
    @click.stop="live.pushEvent('comments_open', { node_id: Number(nodeId) })"
  >
    <MessageCircle class="size-3.5" /><span v-if="count">{{ count }}</span>
  </button>
</template>
