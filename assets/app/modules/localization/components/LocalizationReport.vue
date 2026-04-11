<script setup lang="ts">
import {
  ArrowLeft,
  Box,
  Clapperboard,
  FileText,
  GitBranch,
  MessageSquare,
  Square,
} from "lucide-vue-next";
import type { Component } from "vue";
import { computed } from "vue";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
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
import { useLive } from "@composables/useLive";

interface LanguageProgress {
  localeCode: string;
  name: string;
  final: number;
  total: number;
  percentage: number;
}

interface TargetLanguage {
  localeCode: string;
  name: string;
}

interface SpeakerStat {
  speakerSheetId: number | null;
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
  backUrl,
} = defineProps<{
  languageProgress?: LanguageProgress[];
  targetLanguages?: TargetLanguage[];
  selectedLocale?: string | null;
  speakerStats?: SpeakerStat[];
  voProgress?: VoProgress;
  typeCounts?: Record<string, number>;
  backUrl: string;
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
    label: "None",
    value: voProgress.none,
    color: "text-muted-foreground",
  },
  { label: "Needed", value: voProgress.needed, color: "text-yellow-500" },
  {
    label: "Recorded",
    value: voProgress.recorded,
    color: "text-blue-400",
  },
  {
    label: "Approved",
    value: voProgress.approved,
    color: "text-emerald-500",
  },
]);

function typeIcon(type: string) {
  const icons: Record<string, Component> = {
    flow_node: MessageSquare,
    block: Square,
    sheet: FileText,
    flow: GitBranch,
    screenplay: Clapperboard,
  };
  return icons[type] || Box;
}

function typeLabel(type: string) {
  const labels: Record<string, string> = {
    flow_node: "Nodes",
    block: "Blocks",
    sheet: "Sheets",
    flow: "Flows",
    screenplay: "Screenplays",
  };
  return labels[type] || type;
}
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <!-- Header -->
    <div class="flex items-start justify-between mb-6">
      <div>
        <h1 class="text-lg font-semibold">Localization Report</h1>
        <p class="text-sm text-muted-foreground">Translation progress and statistics</p>
      </div>
      <Button
        variant="ghost"
        size="sm"
        as="a"
        :href="backUrl"
        data-phx-link="redirect"
        data-phx-link-state="push"
      >
        <ArrowLeft class="size-4" />
        Back to Translations
      </Button>
    </div>

    <!-- Progress by Language -->
    <section class="mt-8">
      <h3 class="text-base font-semibold mb-4">Progress by Language</h3>

      <p v-if="languageProgress.length === 0" class="text-sm text-muted-foreground">
        No target languages configured.
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
        </div>
      </div>
    </section>

    <!-- Word Counts by Speaker -->
    <section v-if="selectedLocale && speakerStats.length > 0" class="mt-8">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-base font-semibold">Word Counts by Speaker</h3>
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
              <TableHead class="font-medium text-xs text-muted-foreground">Speaker</TableHead>
              <TableHead class="font-medium text-xs text-muted-foreground text-right"
                >Lines</TableHead
              >
              <TableHead class="font-medium text-xs text-muted-foreground text-right"
                >Words</TableHead
              >
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="stat in speakerStats" :key="stat.speakerSheetId || 'none'">
              <TableCell>
                <span v-if="stat.speakerSheetId">Speaker #{{ stat.speakerSheetId }}</span>
                <span v-else class="text-muted-foreground italic">No speaker</span>
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
      <h3 class="text-base font-semibold mb-4">Voice-Over Progress</h3>
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
      <h3 class="text-base font-semibold mb-4">Content Breakdown</h3>
      <div class="flex gap-3 flex-wrap">
        <Badge
          v-for="[type, count] in typeCountEntries"
          :key="type"
          variant="outline"
          class="gap-1.5 text-sm px-3 py-1"
        >
          <component :is="typeIcon(type)" class="size-3.5" />
          {{ typeLabel(type) }}: {{ count }}
        </Badge>
      </div>
    </section>
  </div>
</template>
