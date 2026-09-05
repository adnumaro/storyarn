<script setup lang="ts">
import { ArrowRight, BookOpen, Check, X } from "@lucide/vue";
import { computed } from "vue";
import type { PlaceholderIssue, SelectedText } from "../../../domain/types";

/**
 * The source string with its context: word count, the placeholders the
 * translation must keep (and whether it does) and the glossary terms it uses.
 */
const {
  text,
  sourceName,
  placeholderIssue = null,
  hasTranslation = false,
} = defineProps<{
  text: SelectedText;
  sourceName: string;
  placeholderIssue?: PlaceholderIssue | null;
  hasTranslation?: boolean;
}>();

interface PlaceholderChip {
  name: string;
  state: "neutral" | "present" | "missing";
}

const placeholderChips = computed<PlaceholderChip[]>(() => {
  const missing = new Set(placeholderIssue?.missing ?? []);
  return Array.from(new Set(text.placeholders)).map((name) => {
    if (!hasTranslation) return { name, state: "neutral" };
    return { name, state: missing.has(name) ? "missing" : "present" };
  });
});

const chipClass: Record<PlaceholderChip["state"], string> = {
  neutral: "border-border text-muted-foreground",
  present: "border-primary/40 text-primary",
  missing: "border-orange-500/50 text-orange-600 dark:text-orange-400",
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      class="flex items-baseline justify-between text-[11px] tracking-[0.06em] text-muted-foreground uppercase"
    >
      <span>{{ $t("localization.editor.source", { source: sourceName }) }}</span>
      <span class="text-xs tracking-normal normal-case">
        {{ $t("localization.editor.words", text.wordCount) }}
      </span>
    </div>

    <div
      class="prose prose-sm max-w-none rounded-md border border-border bg-background px-4 py-3.5 text-[15px] leading-relaxed text-pretty text-foreground dark:prose-invert [&_*]:text-inherit"
      data-testid="localization-source-text"
      v-html="text.sourceHtml"
    />

    <div
      v-if="placeholderChips.length > 0 || text.glossaryHits.length > 0"
      class="flex flex-wrap items-center gap-x-3.5 gap-y-1.5 text-xs text-muted-foreground"
    >
      <span v-if="placeholderChips.length > 0" class="inline-flex flex-wrap items-center gap-1.5">
        <span>{{ $t("localization.editor.placeholders") }}</span>
        <code
          v-for="chip in placeholderChips"
          :key="chip.name"
          :class="[
            'inline-flex items-center gap-1 rounded-full border px-1.5 py-px font-mono text-xs',
            chipClass[chip.state],
          ]"
          :data-placeholder-state="chip.state"
        >
          {{ chip.name }}
          <Check v-if="chip.state === 'present'" class="size-[11px]" aria-hidden="true" />
          <X v-else-if="chip.state === 'missing'" class="size-[11px]" aria-hidden="true" />
          <span v-if="chip.state === 'present'" class="sr-only">
            {{ $t("localization.editor.placeholder_present", { name: chip.name }) }}
          </span>
          <span v-else-if="chip.state === 'missing'" class="sr-only">
            {{ $t("localization.editor.placeholder_missing", { name: chip.name }) }}
          </span>
        </code>
      </span>

      <span v-if="text.glossaryHits.length > 0" class="inline-flex flex-wrap items-center gap-1.5">
        <BookOpen class="size-[13px]" aria-hidden="true" />
        <span>{{ $t("localization.editor.glossary") }}</span>
        <span
          v-for="hit in text.glossaryHits"
          :key="hit.source"
          class="inline-flex items-center gap-1 rounded-full border border-border bg-background px-2 py-px text-xs text-foreground"
        >
          {{ hit.source }}
          <ArrowRight class="size-[11px] text-muted-foreground" aria-hidden="true" />
          {{ hit.target }}
        </span>
      </span>
    </div>
  </div>
</template>
