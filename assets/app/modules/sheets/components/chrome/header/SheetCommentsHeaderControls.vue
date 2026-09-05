<script setup lang="ts">
import { MessageCircle, MessageSquarePlus } from "@lucide/vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useLive } from "@shared/composables/useLive";

const {
  count = 0,
  open = false,
  placing = false,
  canComment = false,
} = defineProps<{
  count: number;
  open: boolean;
  placing?: boolean;
  canComment?: boolean;
}>();

const live = useLive();
</script>

<template>
  <ToolbarTooltip v-if="canComment" :label="$t('sheets.comments.place_hint')" side="bottom">
    <button
      id="sheet-comments-create-mode"
      type="button"
      class="toolbar-btn h-full gap-1.5 px-2 transition-colors"
      :class="placing ? 'bg-primary/10 text-primary' : 'text-muted-foreground'"
      :aria-label="$t('sheets.comments.new_comment_tool')"
      :aria-pressed="placing"
      @click="live.pushEvent('comments_mode', { active: !placing })"
    >
      <MessageSquarePlus class="size-3.5" />
      <span class="hidden sm:inline">{{ $t("sheets.comments.new_comment_tool") }}</span>
    </button>
  </ToolbarTooltip>

  <ToolbarTooltip :label="$t('sheets.comments.title')" side="bottom">
    <button
      id="sheet-comments-toggle"
      type="button"
      class="toolbar-btn h-full gap-1.5 px-2"
      :class="open ? 'text-primary' : 'text-muted-foreground'"
      :aria-label="$t('sheets.comments.title')"
      :aria-expanded="open"
      aria-controls="sheet-comments-panel"
      @click="live.pushEvent(open ? 'comments_close' : 'comments_open', {})"
    >
      <MessageCircle class="size-3.5" />
      <span class="hidden sm:inline">{{ $t("sheets.comments.title") }}</span>
      <span v-if="count" class="text-xs tabular-nums">{{ count }}</span>
    </button>
  </ToolbarTooltip>
</template>
