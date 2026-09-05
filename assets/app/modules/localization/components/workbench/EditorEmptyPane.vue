<script setup lang="ts">
import { ArrowRight, Languages } from "@lucide/vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { TONES, type Tone } from "../../domain/status";
import type { WorkbenchProgress } from "../../domain/types";

/** Nothing selected: offer the next piece of work instead of a blank pane. */
const { progress, canEdit = false } = defineProps<{
  progress: WorkbenchProgress;
  canEdit?: boolean;
}>();

const emit = defineEmits<{ next: [kind: "pending" | "review" | "stale"] }>();

const { t } = useI18n();

interface Shortcut {
  kind: "pending" | "review" | "stale";
  tone: Tone;
  label: string;
  count: number;
}

const shortcuts = computed<Shortcut[]>(() =>
  [
    {
      kind: "pending" as const,
      tone: "pending" as Tone,
      label: t("localization.workbench.empty_pane.next_pending"),
      count: progress.pending,
    },
    {
      kind: "review" as const,
      tone: "review" as Tone,
      label: t("localization.workbench.empty_pane.next_review"),
      count: progress.review,
    },
    {
      kind: "stale" as const,
      tone: "outdated" as Tone,
      label: t("localization.workbench.empty_pane.next_outdated"),
      count: progress.stale,
    },
  ].filter((shortcut) => shortcut.count > 0),
);
</script>

<template>
  <section
    class="flex min-h-0 items-center justify-center rounded-lg border border-dashed border-border bg-card/40 p-8"
    :aria-label="$t('localization.workbench.editor_label')"
  >
    <div class="flex w-full max-w-[380px] flex-col items-center gap-4 text-center">
      <div
        class="flex size-11 items-center justify-center rounded-xl bg-muted text-muted-foreground"
      >
        <Languages class="size-[22px]" />
      </div>
      <div>
        <h2 class="text-base font-semibold">{{ $t("localization.workbench.empty_pane.title") }}</h2>
        <p class="mt-1.5 text-[13px] text-pretty text-muted-foreground">
          {{ $t("localization.workbench.empty_pane.description") }}
        </p>
      </div>
      <div v-if="shortcuts.length > 0" class="flex w-full flex-col gap-2">
        <button
          v-for="shortcut in shortcuts"
          :key="shortcut.kind"
          type="button"
          class="flex items-center gap-2.5 rounded-md border border-border bg-card px-3.5 py-2.5 text-[13px] text-foreground transition-colors hover:bg-accent/60"
          :data-testid="`localization-next-${shortcut.kind}`"
          @click="emit('next', shortcut.kind)"
        >
          <span :class="['size-2 rounded-full', TONES[shortcut.tone].dot]" aria-hidden="true" />
          <span class="flex-1 text-left">{{ shortcut.label }}</span>
          <span class="tabular-nums text-muted-foreground">{{ shortcut.count }}</span>
          <ArrowRight class="size-3.5 text-muted-foreground" />
        </button>
      </div>
      <p v-if="canEdit" class="text-[11px] text-muted-foreground">
        {{ $t("localization.workbench.empty_pane.shortcuts") }}
      </p>
    </div>
  </section>
</template>
