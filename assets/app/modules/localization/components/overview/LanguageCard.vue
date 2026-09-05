<script setup lang="ts">
import { ArrowRight } from "@lucide/vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import LanguageFlag from "@components/language/LanguageFlag.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { STATUS_I18N, percentFinal, type Tone, type TranslationStatus } from "../../domain/status";
import type { LanguageProgress } from "../../domain/types";
import { workbenchUrl } from "../../navigation/workbenchUrl";
import CountChip from "../progress/CountChip.vue";
import SegmentedProgress from "../progress/SegmentedProgress.vue";

/** One target language: how far it is, and every count as a door into its workbench. */
const { language } = defineProps<{ language: LanguageProgress }>();

const { t } = useI18n();

const percent = computed(() => percentFinal(language.final, language.total));

const counts = computed(() => ({
  pending: language.pending,
  draft: language.draft,
  inProgress: language.inProgress,
  review: language.review,
  final: language.final,
}));

interface Chip {
  key: string;
  tone: Tone;
  label: string;
  count: number;
  href: string;
}

const statusOrder: TranslationStatus[] = ["pending", "draft", "in_progress", "review", "final"];

const countByStatus = computed<Record<TranslationStatus, number>>(() => ({
  pending: language.pending,
  draft: language.draft,
  in_progress: language.inProgress,
  review: language.review,
  final: language.final,
}));

const chips = computed<Chip[]>(() => [
  ...statusOrder.map((status) => ({
    key: status,
    tone: status as Tone,
    label: t(STATUS_I18N[status]),
    count: countByStatus.value[status],
    href: workbenchUrl(language.workbenchUrl, { status }),
  })),
  {
    key: "outdated",
    tone: "outdated",
    label: t("localization.flags.outdated"),
    count: language.stale,
    href: workbenchUrl(language.workbenchUrl, { stale: true }),
  },
]);

const remaining = computed(() => Math.max(0, language.total - language.final));
</script>

<template>
  <article
    class="flex flex-col gap-3.5 rounded-lg border border-border bg-card px-5 pt-4 pb-4"
    :data-testid="`localization-language-card-${language.localeCode}`"
  >
    <div class="flex items-center gap-3">
      <LanguageFlag :flag-code="language.flagCode" :short-label="language.shortLabel" size="lg" />
      <div class="min-w-0 flex-1">
        <h3 class="truncate text-base font-semibold">{{ language.name }}</h3>
        <p class="text-xs text-muted-foreground">
          {{
            $t("localization.overview.final_of_total", {
              final: language.final,
              total: language.total,
            })
          }}
          · {{ $t("localization.overview.words", language.wordCount) }}
        </p>
      </div>
      <span class="text-2xl font-semibold tracking-tight tabular-nums">{{ percent }}%</span>
    </div>

    <SegmentedProgress :counts="counts" :total="language.total" />

    <div class="flex flex-wrap gap-1.5">
      <CountChip
        v-for="chip in chips"
        :key="chip.key"
        :tone="chip.tone"
        :label="chip.label"
        :count="chip.count"
        :href="chip.href"
      />
    </div>

    <div class="flex items-center justify-between border-t border-border pt-3">
      <span class="text-xs text-muted-foreground">
        {{ $t("localization.overview.remaining", remaining) }}
      </span>
      <LiveLink
        :to="language.workbenchUrl"
        class="inline-flex items-center gap-1.5 text-[13px] font-medium text-primary hover:text-primary/80"
      >
        {{ $t("localization.overview.open_workbench") }}
        <ArrowRight class="size-3.5" />
      </LiveLink>
    </div>
  </article>
</template>
