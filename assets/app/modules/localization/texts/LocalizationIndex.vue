<script setup lang="ts">
import { ChevronLeft, ChevronRight, Globe, Pencil, Search, Sparkles } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Progress } from "@components/ui/progress";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useLive } from '@shared/composables/useLive.ts';
import DashboardContent from "@shell/DashboardContent.vue";

interface TextEntry {
  id: number;
  sourceText: string;
  translatedText: string | null;
  status: string;
  statusLabel: string;
  sourceType: string;
  sourceTypeLabel: string;
  sourceTypeIcon: string;
  sourceField: string;
  wordCount: number;
  machineTranslated: boolean;
  editUrl: string;
}

const {
  texts = [],
  progress = null,
  totalCount = 0,
  pagination = { page: 1, pageSize: 50 },
  filterStatus = "",
  filterSourceType = "",
  search = "",
  canEdit = false,
  hasProvider = false,
  hasTargetLanguages = false,
} = defineProps<{
  texts?: TextEntry[];
  progress?: { total: number; final: number } | null;
  totalCount?: number;
  pagination?: { page: number; pageSize: number };
  filterStatus?: string;
  filterSourceType?: string;
  search?: string;
  canEdit?: boolean;
  hasProvider?: boolean;
  hasTargetLanguages?: boolean;
}>();

const live = useLive();

const localSearch = ref(search);
let searchTimeout: ReturnType<typeof setTimeout> | null = null;

watch(
  () => search,
  (v) => {
    localSearch.value = v;
  },
);

function onSearchInput(): void {
  if (searchTimeout) {
    clearTimeout(searchTimeout);
  }
  searchTimeout = setTimeout(() => {
    live.pushEvent("search", { search: localSearch.value });
  }, 300);
}

function changeFilter(key: string, value: string): void {
  live.pushEvent("change_filter", { [key]: value });
}

function changePage(newPage: number): void {
  live.pushEvent("change_page", { page: String(newPage) });
}

function translateSingle(id: number): void {
  live.pushEvent("translate_single", { id });
}

const totalPages = computed(() => Math.max(1, Math.ceil(totalCount / pagination.pageSize)));
const progressPercent = computed(() => {
  if (!progress || progress.total === 0) {
    return 0;
  }
  return Math.round((progress.final * 100) / progress.total);
});

const statusVariant: Record<string, string> = {
  pending: "text-muted-foreground bg-muted",
  draft: "text-warning-foreground bg-warning/20",
  in_progress: "text-blue-600 bg-blue-500/10 dark:text-blue-400",
  review: "text-muted-foreground bg-secondary",
  final: "text-green-600 bg-green-500/10 dark:text-green-400",
};
</script>

<template>
  <DashboardContent
    :title="$t('localization.index.title')"
    :subtitle="$t('localization.index.subtitle')"
    :is-empty="!hasTargetLanguages"
    :empty-icon="Globe"
    :empty-message="$t('localization.index.empty_message')"
  >
    <!-- Progress card -->
    <div v-if="progress" class="rounded-2xl border border-border bg-muted/60 p-4">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div class="space-y-1">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">
            {{ $t("localization.index.progress_label") }}
          </p>
          <h2 class="text-lg font-semibold">{{ $t("localization.index.final_translations") }}</h2>
          <p class="text-sm text-muted-foreground">
            {{ $t("localization.index.progress_description") }}
          </p>
        </div>
        <div class="min-w-0 lg:w-72 space-y-2">
          <Progress :model-value="progressPercent" class="w-full" />
          <div class="flex items-center justify-between text-sm text-muted-foreground">
            <span
              >{{ progress.final }} / {{ progress.total }}
              {{ $t("localization.index.final_suffix") }}</span
            >
            <span class="tabular-nums">{{ progressPercent }}%</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Filters row -->
    <div class="flex flex-col gap-3 lg:flex-row lg:items-center">
      <Select
        :model-value="filterStatus"
        @update:model-value="(v: string | string[]) => changeFilter('status', String(v))"
      >
        <SelectTrigger class="w-45">
          <SelectValue :placeholder="$t('localization.index.all_statuses')" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">{{ $t("localization.index.all_statuses") }}</SelectItem>
          <SelectItem value="pending">{{ $t("localization.index.status_pending") }}</SelectItem>
          <SelectItem value="draft">{{ $t("localization.index.status_draft") }}</SelectItem>
          <SelectItem value="in_progress">{{
            $t("localization.index.status_in_progress")
          }}</SelectItem>
          <SelectItem value="review">{{ $t("localization.index.status_review") }}</SelectItem>
          <SelectItem value="final">{{ $t("localization.index.status_final") }}</SelectItem>
        </SelectContent>
      </Select>

      <Select
        :model-value="filterSourceType"
        @update:model-value="(v: string | string[]) => changeFilter('source_type', String(v))"
      >
        <SelectTrigger class="w-45">
          <SelectValue :placeholder="$t('localization.index.all_types')" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">{{ $t("localization.index.all_types") }}</SelectItem>
          <SelectItem value="flow_node">{{ $t("localization.index.type_flow_node") }}</SelectItem>
          <SelectItem value="block">{{ $t("localization.index.type_block") }}</SelectItem>
          <SelectItem value="sheet">{{ $t("localization.index.type_sheet") }}</SelectItem>
          <SelectItem value="flow">{{ $t("localization.index.type_flow") }}</SelectItem>
          <SelectItem value="scene">{{ $t("localization.index.type_scene") }}</SelectItem>
        </SelectContent>
      </Select>

      <div class="relative flex-1">
        <Search class="absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          v-model="localSearch"
          :placeholder="$t('localization.index.search_placeholder')"
          class="pl-8"
          @input="onSearchInput"
        />
      </div>
    </div>

    <!-- Empty state: no matching texts -->
    <div
      v-if="texts.length === 0"
      class="flex flex-col items-center justify-center rounded-lg border border-dashed border-border p-12 text-center"
    >
      <Search class="size-10 text-muted-foreground/50 mb-3" />
      <p class="text-sm text-muted-foreground">{{ $t("localization.index.no_results") }}</p>
    </div>

    <!-- Translation table -->
    <div v-else class="overflow-x-auto rounded-md border">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b bg-muted/50">
            <th class="w-12 px-3 py-2 text-left font-medium text-muted-foreground">
              {{ $t("localization.index.th_type") }}
            </th>
            <th class="px-3 py-2 text-left font-medium text-muted-foreground">
              {{ $t("localization.index.th_source") }}
            </th>
            <th class="px-3 py-2 text-left font-medium text-muted-foreground">
              {{ $t("localization.index.th_translation") }}
            </th>
            <th class="w-28 px-3 py-2 text-left font-medium text-muted-foreground">
              {{ $t("localization.index.th_status") }}
            </th>
            <th class="w-16 px-3 py-2 text-left font-medium text-muted-foreground">
              {{ $t("localization.index.th_words") }}
            </th>
            <th v-if="canEdit" class="w-20 px-3 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="text in texts"
            :key="text.id"
            class="border-b transition-colors hover:bg-muted/50"
          >
            <td class="px-3 py-2">
              <span
                class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground"
                :title="text.sourceTypeLabel"
              >
                {{ text.sourceTypeLabel }}
              </span>
            </td>
            <td class="max-w-xs px-3 py-2">
              <div class="truncate text-sm" :title="text.sourceText">{{ text.sourceText }}</div>
              <div class="text-xs text-muted-foreground">{{ text.sourceField }}</div>
            </td>
            <td class="max-w-xs px-3 py-2">
              <div v-if="text.translatedText" class="truncate text-sm">
                {{ text.translatedText }}
              </div>
              <div v-else class="text-sm text-muted-foreground/50 italic">
                {{ $t("localization.index.not_translated") }}
              </div>
              <span
                v-if="text.machineTranslated"
                class="text-[10px] px-1 rounded border text-muted-foreground"
              >
                MT
              </span>
            </td>
            <td class="px-3 py-2">
              <span
                :class="[
                  'text-xs px-1.5 py-0.5 rounded font-medium',
                  statusVariant[text.status] || statusVariant.pending,
                ]"
              >
                {{ text.statusLabel }}
              </span>
            </td>
            <td class="px-3 py-2 text-sm text-muted-foreground tabular-nums">
              {{ text.wordCount || 0 }}
            </td>
            <td v-if="canEdit" class="px-3 py-2">
              <div class="flex items-center gap-1">
                <a
                  :href="text.editUrl"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="inline-flex items-center justify-center size-7 rounded-md hover:bg-accent transition-colors"
                >
                  <Pencil class="size-3.5" />
                </a>
                <button
                  v-if="hasProvider && !text.translatedText"
                  type="button"
                  class="inline-flex items-center justify-center size-7 rounded-md hover:bg-accent transition-colors"
                  :title="$t('localization.index.translate_deepl_title')"
                  @click="translateSingle(text.id)"
                >
                  <Sparkles class="size-3.5" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Pagination -->
    <div v-if="totalCount > pagination.pageSize" class="flex justify-center">
      <div class="flex items-center gap-1">
        <Button
          variant="outline"
          size="sm"
          :disabled="pagination.page === 1"
          @click="changePage(pagination.page - 1)"
        >
          <ChevronLeft class="size-4" />
        </Button>
        <span class="px-3 text-sm text-muted-foreground tabular-nums">
          {{ $t("localization.index.page_of", { page: pagination.page, total: totalPages }) }}
        </span>
        <Button
          variant="outline"
          size="sm"
          :disabled="pagination.page >= totalPages"
          @click="changePage(pagination.page + 1)"
        >
          <ChevronRight class="size-4" />
        </Button>
      </div>
    </div>
  </DashboardContent>
</template>
