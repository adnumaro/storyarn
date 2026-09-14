<script setup lang="ts">
import { computed } from "vue";
import { Bell, BellOff, Check, CheckCheck, Ellipsis, Link, Move, RotateCcw, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import CommentPill from "./CommentPill.vue";
import CommentReference from "./CommentReference.vue";
import { commentTool } from "./commentTool";
import type { CommentsPanelState, CommentUiConfig } from "./types";
import type { CommentThreadActions } from "./useCommentThreadActions";

/**
 * The reference strip of a conversation: where it lives, its status and the
 * thread-level actions. `variant="card"` is the hub's framed version.
 */
const {
  state,
  ui,
  actions,
  surfaceLabel = null,
  variant = "strip",
  showClose = false,
} = defineProps<{
  state: CommentsPanelState;
  ui: CommentUiConfig;
  /** The conversation's action state, shared with its footer. */
  actions: CommentThreadActions;
  surfaceLabel?: string | null;
  variant?: "strip" | "card";
  showClose?: boolean;
}>();
const emit = defineEmits<{ close: [] }>();
const key = (name: string) => `${ui.i18nPrefix}.${name}`;
const domId = (name: string) => `${ui.domScope}-comment-${name}`;
const thread = computed(() => state.thread);
const sourceType = computed(() => thread.value?.source.type ?? ui.canvasSourceType);
const sourceLabel = computed(
  () => thread.value?.source.label ?? surfaceLabel ?? state.selectedSourceLabel ?? null,
);
const showMenu = computed(() => Boolean(thread.value) && actions.sourceAvailable.value);
const showPreview = computed(
  () => thread.value?.context?.status === "available" && Boolean(thread.value.context.preview),
);
</script>

<template>
  <div
    :class="
      variant === 'card'
        ? 'flex flex-col gap-2.5 rounded-lg border border-border bg-background px-3.5 py-3'
        : 'flex flex-col gap-2 border-b border-border py-2.5 pl-3.5 pr-2'
    "
  >
    <div class="flex min-h-6 items-center gap-1.5">
      <div class="min-w-0 flex-1">
        <CommentReference
          v-if="thread"
          :source-type="thread.source.type"
          :source-label="sourceLabel"
          :source-status="thread.source.status"
          :context="thread.context ?? null"
          :context-id="domId('context')"
          :unavailable-label="$t(key('source_unavailable'))"
          :context-removed-label="$t(key('context_removed'))"
        />
        <div v-else class="flex min-w-0 items-center gap-1.5 text-xs">
          <component
            :is="commentTool(sourceType).icon"
            class="size-3.5 shrink-0"
            :class="commentTool(sourceType).colorClass"
          />
          <span class="truncate font-semibold">{{ sourceLabel ?? $t(key("new_thread")) }}</span>
        </div>
      </div>
      <CommentPill v-if="!thread" kind="draft">{{ $t(key("draft")) }}</CommentPill>
      <CommentPill v-else-if="thread.status === 'resolved'" kind="resolved">{{
        $t(key("resolved"))
      }}</CommentPill>
      <CommentPill v-else kind="open">{{ $t(key("open")) }}</CommentPill>
      <Button
        v-if="thread && actions.canChangeStatus.value"
        :id="domId('status')"
        variant="ghost"
        size="icon-xs"
        :title="$t(key(thread.status === 'open' ? 'resolve' : 'reopen'))"
        :aria-label="$t(key(thread.status === 'open' ? 'resolve' : 'reopen'))"
        :disabled="actions.pending.value"
        @click="actions.setStatus(thread.status === 'open' ? 'resolved' : 'open')"
      >
        <Check v-if="thread.status === 'open'" class="size-3.5" />
        <RotateCcw v-else class="size-3.5" />
      </Button>
      <DropdownMenu v-if="showMenu && thread">
        <DropdownMenuTrigger as-child>
          <Button
            :id="domId('menu')"
            variant="ghost"
            size="icon-xs"
            :aria-label="$t(key('more_actions'))"
            :disabled="actions.pending.value"
          >
            <Ellipsis class="size-3.5" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" :side-offset="4" class="w-44">
          <DropdownMenuItem :id="domId('follow')" @select="actions.toggleFollow()">
            <BellOff v-if="thread.following" class="size-3.5" /><Bell v-else class="size-3.5" />
            {{ $t(key(thread.following ? "unfollow" : "follow")) }}
          </DropdownMenuItem>
          <DropdownMenuItem v-if="thread.unread" :id="domId('read')" @select="actions.markRead()">
            <CheckCheck class="size-3.5" />{{ $t(key("mark_read")) }}
          </DropdownMenuItem>
          <DropdownMenuItem :id="domId('copy-link')" @select="actions.copyLink()">
            <Link class="size-3.5" />{{
              $t(key(actions.linkCopied.value ? "link_copied" : "copy_link"))
            }}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <Button
        v-if="showClose"
        :id="`${ui.domScope}-comment-popover-close`"
        variant="ghost"
        size="icon-xs"
        :aria-label="$t(key('close'))"
        @click="emit('close')"
      >
        <X class="size-3.5" />
      </Button>
    </div>
    <CommentReference
      v-if="showPreview && thread"
      :source-type="thread.source.type"
      :context="thread.context"
      :crumb="false"
      preview
      :unavailable-label="$t(key('source_unavailable'))"
      :context-removed-label="$t(key('context_removed'))"
    />
    <p v-if="!thread" class="flex items-center gap-1.5 text-[11px] text-muted-foreground">
      <Move class="size-[11px]" />{{ $t(key("draft_hint")) }}
    </p>
    <p v-if="actions.error.value" role="alert" class="text-xs text-destructive">
      {{ actions.error.value }}
    </p>
  </div>
</template>
