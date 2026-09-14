<script setup lang="ts">
import { computed } from "vue";
import { ChevronRight } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import CommentPill from "./CommentPill.vue";
import { commentContextIcon, commentContextKind, commentTool } from "./commentTool";
import type { CommentContext } from "./types";

/**
 * Where a conversation lives: tool › container › context, plus the flags that
 * say the context or the source is gone (`crumb`), and the live description of
 * the context target: its kind, label and current value (`preview`).
 */
const {
  sourceType,
  sourceLabel = null,
  sourceStatus = "available",
  context = null,
  crumb = true,
  preview = false,
  contextId = null,
  unavailableLabel,
  contextRemovedLabel,
} = defineProps<{
  sourceType: string;
  sourceLabel?: string | null;
  sourceStatus?: "available" | "unavailable";
  context?: CommentContext | null;
  crumb?: boolean;
  preview?: boolean;
  /** Stable DOM id for the context part of the crumb, present only when there is a context. */
  contextId?: string | null;
  unavailableLabel: string;
  contextRemovedLabel: string;
}>();

const { t, n } = useI18n();
const tool = computed(() => commentTool(sourceType));
const contextAvailable = computed(() => context?.status === "available");
const showPreview = computed(() => preview && Boolean(context?.preview) && contextAvailable.value);
const kind = computed(() =>
  context ? commentContextKind(context.type, context.preview?.kind) : "",
);
const kindIcon = computed(() =>
  context ? commentContextIcon(context.type, context.preview?.kind) : null,
);
const value = computed(() => {
  const raw = context?.preview?.value;
  if (raw == null || raw === "") return null;
  if (typeof raw === "boolean") return t(raw ? "comments.values.yes" : "comments.values.no");
  if (typeof raw === "number") return n(raw);
  return raw;
});
const kindLabel = computed(() => {
  const label = t(`comments.kinds.${kind.value}`);
  return label === `comments.kinds.${kind.value}` ? kind.value : label;
});
</script>

<template>
  <div class="flex min-w-0 flex-col gap-2">
    <div v-if="crumb" class="flex min-w-0 items-center gap-1.5 text-xs">
      <component :is="tool.icon" class="size-3.5 shrink-0" :class="tool.colorClass" />
      <span
        v-if="sourceLabel"
        class="min-w-0 truncate"
        :class="context ? 'text-muted-foreground' : 'font-semibold'"
        >{{ sourceLabel }}</span
      >
      <span v-if="context" :id="contextId ?? undefined" class="flex min-w-0 items-center gap-1.5">
        <ChevronRight class="size-3 shrink-0 text-muted-foreground" />
        <span
          class="truncate font-semibold"
          :class="{ 'text-muted-foreground line-through': !contextAvailable }"
          >{{ context.label }}</span
        >
        <CommentPill v-if="!contextAvailable" kind="context-removed">{{
          contextRemovedLabel
        }}</CommentPill>
      </span>
      <CommentPill v-if="sourceStatus === 'unavailable'" kind="source-unavailable">{{
        unavailableLabel
      }}</CommentPill>
    </div>
    <div
      v-if="showPreview && context"
      class="flex min-w-0 items-center gap-2 rounded-md border border-border bg-background px-2.5 py-1.5 text-xs"
      :data-comment-reference-kind="kind"
    >
      <component :is="kindIcon" class="size-3.5 shrink-0 text-muted-foreground" />
      <span class="shrink-0 font-medium">{{ context.label }}</span>
      <span class="min-w-0 flex-1 truncate text-muted-foreground">{{ value ?? kindLabel }}</span>
    </div>
  </div>
</template>
