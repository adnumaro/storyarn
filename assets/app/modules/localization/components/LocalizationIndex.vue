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
import { useLive } from "@composables/useLive";
import DashboardContent from "@components/layout/DashboardContent.vue";

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
    title="Localization"
    subtitle="Review source strings, filter translations, and track progress for every target language."
    :is-empty="!hasTargetLanguages"
    :empty-icon="Globe"
    empty-message="Use the sidebar to add a target language and start translating."
  >
    <!-- Progress card -->
    <div v-if="progress" class="rounded-2xl border border-border bg-muted/60 p-4">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div class="space-y-1">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">
            Progress
          </p>
          <h2 class="text-lg font-semibold">Final translations</h2>
          <p class="text-sm text-muted-foreground">
            Measure the strings that are ready to ship in the active language.
          </p>
        </div>
        <div class="min-w-0 lg:w-72 space-y-2">
          <Progress :model-value="progressPercent" class="w-full" />
          <div class="flex items-center justify-between text-sm text-muted-foreground">
            <span>{{ progress.final }} / {{ progress.total }} final</span>
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
          <SelectValue placeholder="All statuses" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All statuses</SelectItem>
          <SelectItem value="pending">Pending</SelectItem>
          <SelectItem value="draft">Draft</SelectItem>
          <SelectItem value="in_progress">In progress</SelectItem>
          <SelectItem value="review">Review</SelectItem>
          <SelectItem value="final">Final</SelectItem>
        </SelectContent>
      </Select>

      <Select
        :model-value="filterSourceType"
        @update:model-value="(v: string | string[]) => changeFilter('source_type', String(v))"
      >
        <SelectTrigger class="w-45">
          <SelectValue placeholder="All types" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All types</SelectItem>
          <SelectItem value="flow_node">Flow node</SelectItem>
          <SelectItem value="block">Block</SelectItem>
          <SelectItem value="sheet">Sheet</SelectItem>
          <SelectItem value="flow">Flow</SelectItem>
          <SelectItem value="scene">Scene</SelectItem>
        </SelectContent>
      </Select>

      <div class="relative flex-1">
        <Search class="absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          v-model="localSearch"
          placeholder="Search in source or translation..."
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
      <p class="text-sm text-muted-foreground">No translations found matching your filters.</p>
    </div>

    <!-- Translation table -->
    <div v-else class="overflow-x-auto rounded-md border">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b bg-muted/50">
            <th class="w-12 px-3 py-2 text-left font-medium text-muted-foreground">Type</th>
            <th class="px-3 py-2 text-left font-medium text-muted-foreground">Source Text</th>
            <th class="px-3 py-2 text-left font-medium text-muted-foreground">Translation</th>
            <th class="w-28 px-3 py-2 text-left font-medium text-muted-foreground">Status</th>
            <th class="w-16 px-3 py-2 text-left font-medium text-muted-foreground">Words</th>
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
              <div v-else class="text-sm text-muted-foreground/50 italic">Not translated</div>
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
                  title="Translate with DeepL"
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
          Page {{ pagination.page }} of {{ totalPages }}
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
