<script setup lang="ts">
import { Box, MessageSquare, Square, UserRound } from "lucide-vue-next";
import type { Component } from "vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Progress } from "@components/ui/progress";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table";
import { useLive } from "@shared/composables/useLive.ts";

const { t } = useI18n();

interface LanguageProgress {
  localeCode: string;
  name: string;
  final: number;
  review: number;
  stale: number;
  total: number;
  percentage: number;
}

interface TargetLanguage {
  localeCode: string;
  name: string;
}

interface SpeakerStat {
  speakerSheetId: number | null;
  speakerName: string | null;
  lineCount: number;
  wordCount: number;
}

interface VoProgress {
  none: number;
  needed: number;
  recorded: number;
  approved: number;
}

const {
  languageProgress = [],
  targetLanguages = [],
  selectedLocale = null,
  speakerStats = [],
  voProgress = { none: 0, needed: 0, recorded: 0, approved: 0 },
  typeCounts = {},
} = defineProps<{
  languageProgress?: LanguageProgress[];
  targetLanguages?: TargetLanguage[];
  selectedLocale?: string | null;
  speakerStats?: SpeakerStat[];
  voProgress?: VoProgress;
  typeCounts?: Record<string, number>;
}>();

const live = useLive();

function changeLocale(value: string) {
  live.pushEvent("change_locale", { locale: value });
}

const typeCountEntries = computed(() => {
  return Object.entries(typeCounts);
});

const voStats = computed(() => [
  {
    label: t("localization.report.vo_none"),
    value: voProgress.none,
    color: "text-muted-foreground",
  },
  { label: t("localization.report.vo_needed"), value: voProgress.needed, color: "text-yellow-500" },
  {
    label: t("localization.report.vo_recorded"),
    value: voProgress.recorded,
    color: "text-blue-400",
  },
  {
    label: t("localization.report.vo_approved"),
    value: voProgress.approved,
    color: "text-emerald-500",
  },
]);

function typeIcon(type: string) {
  const icons: Record<string, Component> = {
    flow_node: MessageSquare,
    block: Square,
    sheet: UserRound,
  };
  return icons[type] || Box;
}

const typeKeys: Record<string, string> = {
  flow_node: "localization.report.types.flow_node",
  block: "localization.report.types.block",
  sheet: "localization.report.types.sheet",
};
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <!-- Header -->
    <div class="flex items-start justify-between mb-6">
      <div>
        <h1 class="text-lg font-semibold">{{ $t("localization.report.title") }}</h1>
        <p class="text-sm text-muted-foreground">{{ $t("localization.report.subtitle") }}</p>
      </div>
    </div>

    <!-- Progress by Language -->
    <section class="mt-8">
      <h3 class="text-base font-semibold mb-4">
        {{ $t("localization.report.progress_by_language") }}
      </h3>

      <p v-if="languageProgress.length === 0" class="text-sm text-muted-foreground">
        {{ $t("localization.report.no_targets_configured") }}
      </p>

      <div class="space-y-3">
        <div
          v-for="lang in languageProgress"
          :key="lang.localeCode"
          class="flex items-center gap-4 bg-muted rounded-lg p-3"
        >
          <span class="font-mono text-sm w-12">{{ lang.localeCode }}</span>
          <span class="w-24">{{ lang.name }}</span>
          <Progress :model-value="lang.final" :max="Math.max(lang.total, 1)" class="flex-1" />
          <span class="text-sm font-medium w-20 text-right">{{ lang.percentage }}%</span>
          <span class="text-xs text-muted-foreground w-24 text-right">
            {{ lang.final }}/{{ lang.total }}
          </span>
          <Badge v-if="lang.stale" variant="destructive" class="shrink-0">
            {{ $t("localization.report.stale_count", { count: lang.stale }) }}
          </Badge>
        </div>
      </div>
    </section>

    <!-- Word Counts by Speaker -->
    <section v-if="selectedLocale && speakerStats.length > 0" class="mt-8">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-base font-semibold">
          {{ $t("localization.report.word_counts_by_speaker") }}
        </h3>
        <Select
          :model-value="selectedLocale"
          @update:model-value="(v: string | string[]) => changeLocale(Array.isArray(v) ? v[0] : v)"
        >
          <SelectTrigger class="w-40 h-8">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem
              v-for="lang in targetLanguages"
              :key="lang.localeCode"
              :value="lang.localeCode"
            >
              {{ lang.name }}
            </SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div class="rounded-lg border border-border bg-surface overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow class="bg-muted/40 hover:bg-muted/40">
              <TableHead class="font-medium text-xs text-muted-foreground">{{
                $t("localization.report.speaker_header")
              }}</TableHead>
              <TableHead class="font-medium text-xs text-muted-foreground text-right">{{
                $t("localization.report.lines_header")
              }}</TableHead>
              <TableHead class="font-medium text-xs text-muted-foreground text-right">{{
                $t("localization.report.words_header")
              }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="stat in speakerStats" :key="stat.speakerSheetId || 'none'">
              <TableCell>
                <span v-if="stat.speakerName">{{ stat.speakerName }}</span>
                <span v-else-if="stat.speakerSheetId">{{
                  $t("localization.report.speaker_id", { id: stat.speakerSheetId })
                }}</span>
                <span v-else class="text-muted-foreground italic">{{
                  $t("localization.report.no_speaker")
                }}</span>
              </TableCell>
              <TableCell class="text-right tabular-nums">{{ stat.lineCount }}</TableCell>
              <TableCell class="text-right tabular-nums">{{ stat.wordCount }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
    </section>

    <!-- VO Progress -->
    <section v-if="selectedLocale" class="mt-8">
      <h3 class="text-base font-semibold mb-4">{{ $t("localization.report.vo_progress") }}</h3>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div
          v-for="stat in voStats"
          :key="stat.label"
          class="rounded-lg border border-border bg-surface p-4 space-y-1"
        >
          <div class="text-xs text-muted-foreground">{{ stat.label }}</div>
          <div :class="['text-2xl font-bold tabular-nums', stat.color]">{{ stat.value }}</div>
        </div>
      </div>
    </section>

    <!-- Content Type Breakdown -->
    <section v-if="selectedLocale && typeCountEntries.length > 0" class="mt-8">
      <h3 class="text-base font-semibold mb-4">
        {{ $t("localization.report.content_breakdown") }}
      </h3>
      <div class="flex gap-3 flex-wrap">
        <Badge
          v-for="[type, count] in typeCountEntries"
          :key="type"
          variant="outline"
          class="gap-1.5 text-sm px-3 py-1"
        >
          <component :is="typeIcon(type)" class="size-3.5" />
          {{ typeKeys[type] ? $t(typeKeys[type]) : type }}: {{ count }}
        </Badge>
      </div>
    </section>
  </div>
</template>
