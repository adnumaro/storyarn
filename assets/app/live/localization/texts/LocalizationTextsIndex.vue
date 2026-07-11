<script setup lang="ts">
import {
  AlertTriangle,
  Check,
  ChevronLeft,
  ChevronRight,
  CircleDot,
  Clock3,
  Globe,
  LoaderCircle,
  Lock,
  Search,
  Sparkles,
  X,
} from "lucide-vue-next";
import { computed, nextTick, onBeforeUnmount, ref, watch } from "vue";
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
import { Textarea } from "@components/ui/textarea";
import { useLive } from "@shared/composables/useLive.ts";
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
  stale: boolean;
  editUrl: string;
}

interface SelectedText {
  id: number;
  sourceType: string;
  sourceTypeLabel: string;
  sourceField: string;
  sourceReference: string;
  sourceHtml: string;
  sourceText: string;
  wordCount: number;
  localeCode: string;
  localeName: string;
  translatedText: string;
  status: string;
  translatorNotes: string;
  voStatus: string;
  machineTranslated: boolean;
  lastTranslatedAt: string | null;
  stale: boolean;
  placeholders: string[];
  lockVersion: number;
}

interface SaveResponse {
  ok?: boolean;
  conflict?: boolean;
  error?: string;
  errors?: Record<string, string>;
  text?: SelectedText;
}

const {
  texts = [],
  progress = null,
  totalCount = 0,
  pagination = { page: 1, pageSize: 50 },
  filters = { status: "", sourceType: "", search: "" },
  capabilities = { canEdit: false, hasProvider: false, hasTargetLanguages: false },
  selectedText = null,
  selectedLocaleName = "",
} = defineProps<{
  texts?: TextEntry[];
  progress?: { total: number; final: number; stale?: number } | null;
  totalCount?: number;
  pagination?: { page: number; pageSize: number };
  filters?: { status: string; sourceType: string; search: string };
  capabilities?: { canEdit: boolean; hasProvider: boolean; hasTargetLanguages: boolean };
  selectedText?: SelectedText | null;
  selectedLocaleName?: string;
}>();

const live = useLive();
const filterStatus = computed(() => filters.status);
const filterSourceType = computed(() => filters.sourceType);
const search = computed(() => filters.search);
const canEdit = computed(() => capabilities.canEdit);
const hasProvider = computed(() => capabilities.hasProvider);
const hasTargetLanguages = computed(() => capabilities.hasTargetLanguages);
const localSearch = ref(search.value);
const translatedText = ref("");
const status = ref("pending");
const translatorNotes = ref("");
const voStatus = ref("none");
const localLockVersion = ref(1);
const saveState = ref<"idle" | "dirty" | "saving" | "saved" | "error" | "conflict">("idle");
const saveError = ref("");
const translating = ref(false);
const hydrating = ref(false);
const lastSavedSnapshot = ref("");
const conflictVersion = ref<number | null>(null);
const conflictText = ref<SelectedText | null>(null);
let searchTimeout: ReturnType<typeof setTimeout> | null = null;
let autosaveTimeout: ReturnType<typeof setTimeout> | null = null;
let savedTimeout: ReturnType<typeof setTimeout> | null = null;
let pendingSave: { id: number; snapshot: string } | null = null;

const statusOptions = computed(() => [
  { key: "pending", label: "localization.index.status_pending" },
  { key: "draft", label: "localization.index.status_draft" },
  { key: "in_progress", label: "localization.index.status_in_progress" },
  { key: "review", label: "localization.index.status_review" },
  { key: "final", label: "localization.index.status_final" },
]);

const voStatusOptions = computed(() => [
  { key: "none", label: "localization.edit.vo_none" },
  { key: "needed", label: "localization.edit.vo_needed" },
  { key: "recorded", label: "localization.edit.vo_recorded" },
  { key: "approved", label: "localization.edit.vo_approved" },
]);

const totalPages = computed(() => Math.max(1, Math.ceil(totalCount / pagination.pageSize)));
const progressPercent = computed(() => {
  if (!progress || progress.total === 0) return 0;
  return Math.round((progress.final * 100) / progress.total);
});

const currentIndex = computed(() => texts.findIndex((text) => text.id === selectedText?.id));
const previousText = computed(() =>
  currentIndex.value > 0 ? texts[currentIndex.value - 1] : null,
);
const nextText = computed(() =>
  currentIndex.value >= 0 && currentIndex.value < texts.length - 1
    ? texts[currentIndex.value + 1]
    : null,
);

const currentSnapshot = computed(() =>
  JSON.stringify({
    translatedText: translatedText.value,
    status: status.value,
    translatorNotes: translatorNotes.value,
    voStatus: voStatus.value,
  }),
);
const dirty = computed(() => currentSnapshot.value !== lastSavedSnapshot.value);

const placeholderIssue = computed(() => {
  if (!selectedText || translatedText.value.trim() === "") return null;

  const expected = frequencies(selectedText.placeholders);
  const actual = frequencies(translatedText.value.match(/\{[^{}\r\n]+\}/g) ?? []);
  const missing = difference(expected, actual);
  const extra = difference(actual, expected);

  if (missing.length === 0 && extra.length === 0) return null;
  return { missing, extra };
});

const finalUnavailable = computed(
  () => translatedText.value.trim() === "" || placeholderIssue.value !== null,
);

const statusClasses: Record<string, string> = {
  pending: "badge-ghost",
  draft: "badge-warning",
  in_progress: "badge-info",
  review: "badge-secondary",
  final: "badge-success",
};

watch(search, (value) => {
  localSearch.value = value;
});

watch(
  () => selectedText,
  (text) => {
    const activeSave = pendingSave;
    const hasNewerLocalEdit =
      activeSave !== null &&
      activeSave.id === text?.id &&
      currentSnapshot.value !== activeSave.snapshot;

    if (!hasNewerLocalEdit) hydrateEditor(text);
  },
  { immediate: true },
);

watch(translatedText, (value, previous) => {
  if (!hydrating.value && value !== previous) {
    if (value.trim() === "") status.value = "pending";
    else if (status.value === "pending" || status.value === "final") status.value = "draft";
  }
});

watch([translatedText, status, translatorNotes, voStatus], () => {
  if (hydrating.value || !selectedText || !canEdit.value) return;
  if (!dirty.value) return;

  saveState.value = "dirty";
  scheduleAutosave();
});

onBeforeUnmount(() => {
  if (searchTimeout) clearTimeout(searchTimeout);
  if (autosaveTimeout) clearTimeout(autosaveTimeout);
  if (savedTimeout) clearTimeout(savedTimeout);
});

function hydrateEditor(text: SelectedText | null | undefined): void {
  const editor = text
    ? {
        translatedText: text.translatedText,
        status: text.status,
        translatorNotes: text.translatorNotes,
        voStatus: text.voStatus,
        lockVersion: text.lockVersion,
      }
    : {
        translatedText: "",
        status: "pending",
        translatorNotes: "",
        voStatus: "none",
        lockVersion: 1,
      };

  hydrating.value = true;
  translatedText.value = editor.translatedText;
  status.value = editor.status;
  translatorNotes.value = editor.translatorNotes;
  voStatus.value = editor.voStatus;
  localLockVersion.value = editor.lockVersion;
  conflictVersion.value = null;
  conflictText.value = null;
  saveError.value = "";
  saveState.value = "idle";

  nextTick(() => {
    lastSavedSnapshot.value = currentSnapshot.value;
    hydrating.value = false;
  });
}

function onSearchInput(): void {
  if (searchTimeout) clearTimeout(searchTimeout);
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

function scheduleAutosave(): void {
  if (autosaveTimeout) clearTimeout(autosaveTimeout);
  autosaveTimeout = setTimeout(() => saveTranslation(), 900);
}

function saveAllowed(text: SelectedText | null | undefined): text is SelectedText {
  return !!text && canEdit.value && saveState.value !== "saving" && !placeholderIssue.value;
}

function saveTranslation(advance = false, onSuccess?: () => void, onFailure?: () => void): void {
  if (!saveAllowed(selectedText)) {
    onFailure?.();
    return;
  }

  if (autosaveTimeout) clearTimeout(autosaveTimeout);

  if (!dirty.value && !advance) {
    onSuccess?.();
    return;
  }

  saveState.value = "saving";
  saveError.value = "";
  const request = { id: selectedText.id, snapshot: currentSnapshot.value };
  pendingSave = request;

  live.pushEvent(
    "save_translation",
    {
      id: selectedText.id,
      lock_version: localLockVersion.value,
      localized_text: {
        translated_text: translatedText.value,
        status: status.value,
        translator_notes: translatorNotes.value,
        vo_status: voStatus.value,
      },
    },
    (response: SaveResponse) =>
      handleSaveResponse(response, request, advance, onSuccess, onFailure),
    () => {
      pendingSave = null;
      handleSaveError({ error: "save_failed" });
      onFailure?.();
    },
  );
}

function handleSaveResponse(
  response: SaveResponse,
  request: { id: number; snapshot: string },
  advance: boolean,
  onSuccess?: () => void,
  onFailure?: () => void,
): void {
  pendingSave = null;

  if (response?.ok) {
    handleSaveSuccess(response.text, request, advance, onSuccess, onFailure);
  } else if (response?.conflict && response.text) {
    handleSaveConflict(response.text);
    onFailure?.();
  } else {
    handleSaveError(response);
    onFailure?.();
  }
}

function handleSaveSuccess(
  savedText: SelectedText | undefined,
  request: { id: number; snapshot: string },
  advance: boolean,
  onSuccess?: () => void,
  onFailure?: () => void,
): void {
  const hasNewerLocalEdit =
    selectedText?.id === request.id && currentSnapshot.value !== request.snapshot;

  if (hasNewerLocalEdit) {
    if (savedText) localLockVersion.value = savedText.lockVersion;
    lastSavedSnapshot.value = request.snapshot;
    saveState.value = "dirty";
    saveTranslation(advance, onSuccess, onFailure);
    return;
  }

  if (savedText) hydrateEditor(savedText);
  lastSavedSnapshot.value = request.snapshot;
  saveState.value = "saved";
  if (savedTimeout) clearTimeout(savedTimeout);
  savedTimeout = setTimeout(() => (saveState.value = "idle"), 1800);
  onSuccess?.();
  if (advance) selectRelative("next");
}

function handleSaveConflict(latestText: SelectedText): void {
  conflictVersion.value = latestText.lockVersion;
  conflictText.value = latestText;
  saveState.value = "conflict";
  saveError.value = "conflict";
}

function handleSaveError(response: SaveResponse): void {
  saveState.value = "error";
  saveError.value = response?.errors
    ? Object.values(response.errors).join(" · ")
    : response?.error || "save_failed";
}

function retryAfterConflict(): void {
  if (conflictVersion.value === null) return;
  localLockVersion.value = conflictVersion.value;
  conflictVersion.value = null;
  conflictText.value = null;
  saveTranslation();
}

function reloadAfterConflict(): void {
  if (conflictText.value) hydrateEditor(conflictText.value);
}

function requestSelection(id: number): void {
  const navigate = () => live.pushEvent("select_text", { id });
  if (dirty.value && canEdit.value) saveTranslation(false, navigate);
  else navigate();
}

function closeEditor(): void {
  const close = () => live.pushEvent("close_editor", {});
  if (dirty.value && canEdit.value) saveTranslation(false, close);
  else close();
}

function selectRelative(direction: "previous" | "next"): void {
  const target = direction === "previous" ? previousText.value : nextText.value;
  if (target) requestSelection(target.id);
}

function translateSingle(id: number): void {
  if (translating.value) return;
  translating.value = true;

  const translate = () => {
    live.pushEvent(
      "translate_single",
      { id },
      (response: SaveResponse) => {
        translating.value = false;
        if (response?.ok && response.text) hydrateEditor(response.text);
        else if (!response?.ok) {
          saveState.value = "error";
          saveError.value = response?.error || "translation_failed";
        }
      },
      () => {
        translating.value = false;
        saveState.value = "error";
        saveError.value = "translation_failed";
      },
    );
  };

  if (dirty.value && selectedText)
    saveTranslation(false, translate, () => (translating.value = false));
  else translate();
}

function onEditorKeydown(event: KeyboardEvent): void {
  if (!(event.metaKey || event.ctrlKey) || event.key !== "Enter") return;
  event.preventDefault();
  saveTranslation(event.shiftKey);
}

function frequencies(items: string[]): Map<string, number> {
  const result = new Map<string, number>();
  for (const item of items) result.set(item, (result.get(item) ?? 0) + 1);
  return result;
}

function difference(left: Map<string, number>, right: Map<string, number>): string[] {
  const result: string[] = [];
  for (const [item, count] of left) {
    for (let i = 0; i < Math.max(0, count - (right.get(item) ?? 0)); i += 1) result.push(item);
  }
  return result;
}
</script>

<template>
  <DashboardContent
    :title="$t('localization.index.title')"
    :subtitle="$t('localization.index.subtitle')"
    :is-empty="!hasTargetLanguages"
    :empty-icon="Globe"
    :empty-message="$t('localization.index.empty_message')"
  >
    <div v-if="progress" :class="['grid gap-3 sm:grid-cols-3', selectedText && 'hidden lg:grid']">
      <div class="rounded-xl border border-base-300 bg-base-100 p-3.5 shadow-sm">
        <div
          class="flex items-center justify-between text-xs font-semibold uppercase tracking-wide text-base-content/55"
        >
          <span>{{ $t("localization.index.progress_label") }}</span>
          <span class="tabular-nums">{{ progressPercent }}%</span>
        </div>
        <Progress :model-value="progressPercent" class="mt-3" />
        <p class="mt-2 text-xs text-base-content/60">
          {{ progress.final }} / {{ progress.total }} {{ $t("localization.index.final_suffix") }}
        </p>
      </div>
      <div class="rounded-xl border border-base-300 bg-base-100 p-3.5 shadow-sm">
        <div
          class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/55"
        >
          <CircleDot class="size-3.5 text-warning" />
          {{ $t("localization.index.needs_attention") }}
        </div>
        <p class="mt-2 text-2xl font-semibold tabular-nums">
          {{ progress.total - progress.final }}
        </p>
      </div>
      <div class="rounded-xl border border-base-300 bg-base-100 p-3.5 shadow-sm">
        <div
          class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/55"
        >
          <AlertTriangle class="size-3.5 text-error" />
          {{ $t("localization.index.stale_translations") }}
        </div>
        <p class="mt-2 text-2xl font-semibold tabular-nums">{{ progress.stale || 0 }}</p>
      </div>
    </div>

    <div
      :class="['flex flex-col gap-3 lg:flex-row lg:items-center', selectedText && 'hidden lg:flex']"
    >
      <Select
        :model-value="filterStatus"
        @update:model-value="(value: string | string[]) => changeFilter('status', String(value))"
      >
        <SelectTrigger class="w-full lg:w-44">
          <SelectValue :placeholder="$t('localization.index.all_statuses')" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">{{ $t("localization.index.all_statuses") }}</SelectItem>
          <SelectItem v-for="option in statusOptions" :key="option.key" :value="option.key">
            {{ $t(option.label) }}
          </SelectItem>
        </SelectContent>
      </Select>

      <Select
        :model-value="filterSourceType"
        @update:model-value="
          (value: string | string[]) => changeFilter('source_type', String(value))
        "
      >
        <SelectTrigger class="w-full lg:w-44">
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
        <Search
          class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-base-content/45"
        />
        <Input
          v-model="localSearch"
          :placeholder="$t('localization.index.search_placeholder')"
          class="pl-9"
          @input="onSearchInput"
        />
      </div>
    </div>

    <div class="grid min-h-0 gap-4 lg:grid-cols-[minmax(19rem,0.82fr)_minmax(30rem,1.45fr)]">
      <section
        :class="[
          'min-w-0 flex-col overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm',
          selectedText ? 'hidden lg:flex' : 'flex',
        ]"
        :aria-label="$t('localization.index.strings_list')"
      >
        <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
          <div>
            <h2 class="font-semibold">{{ selectedLocaleName }}</h2>
            <p class="text-xs text-base-content/55">
              {{ $t("localization.index.string_count", { count: totalCount }) }}
            </p>
          </div>
          <span class="badge badge-ghost badge-sm">{{ pagination.page }} / {{ totalPages }}</span>
        </div>

        <div
          v-if="texts.length === 0"
          class="flex flex-1 flex-col items-center justify-center p-10 text-center"
        >
          <Search class="mb-3 size-9 text-base-content/25" />
          <p class="text-sm text-base-content/55">{{ $t("localization.index.no_results") }}</p>
        </div>

        <div
          v-else
          class="max-h-[62vh] divide-y divide-base-300 overflow-y-auto overscroll-contain"
        >
          <article
            v-for="text in texts"
            :key="text.id"
            :class="[
              'group relative flex items-start gap-2 p-2 transition-colors',
              selectedText?.id === text.id ? 'bg-primary/8' : 'hover:bg-base-200/70',
            ]"
          >
            <button
              type="button"
              class="min-w-0 flex-1 rounded-lg p-2 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              :aria-current="selectedText?.id === text.id ? 'true' : undefined"
              @click="requestSelection(text.id)"
            >
              <div class="flex items-center gap-2">
                <span :class="['badge badge-xs', statusClasses[text.status] || 'badge-ghost']">
                  {{ text.statusLabel }}
                </span>
                <span v-if="text.stale" class="badge badge-error badge-outline badge-xs">
                  {{ $t("localization.index.stale") }}
                </span>
                <span class="ml-auto text-[11px] text-base-content/45">{{ text.wordCount }}w</span>
              </div>
              <p class="mt-2 line-clamp-2 text-sm font-medium leading-relaxed">
                {{ text.sourceText }}
              </p>
              <p
                :class="[
                  'mt-1 line-clamp-1 text-xs',
                  text.translatedText ? 'text-base-content/60' : 'italic text-base-content/35',
                ]"
              >
                {{ text.translatedText || $t("localization.index.not_translated") }}
              </p>
              <p class="mt-1.5 text-[11px] text-base-content/40">
                {{ text.sourceTypeLabel }} · {{ text.sourceField }}
              </p>
            </button>
            <button
              v-if="canEdit && hasProvider"
              type="button"
              :data-testid="`localization-translate-${text.id}`"
              class="btn btn-ghost btn-xs btn-square mt-1 opacity-0 transition-opacity group-hover:opacity-100 focus:opacity-100"
              :aria-label="$t('localization.index.translate_deepl_title')"
              :disabled="translating"
              @click="translateSingle(text.id)"
            >
              <Sparkles class="size-3.5" />
            </button>
          </article>
        </div>

        <div
          v-if="totalCount > pagination.pageSize"
          class="flex items-center justify-between border-t border-base-300 p-2"
        >
          <Button
            variant="ghost"
            size="sm"
            :disabled="pagination.page === 1"
            :aria-label="$t('localization.index.previous_page')"
            @click="changePage(pagination.page - 1)"
          >
            <ChevronLeft class="size-4" />
          </Button>
          <span class="text-xs text-base-content/50">
            {{ $t("localization.index.page_of", { page: pagination.page, total: totalPages }) }}
          </span>
          <Button
            variant="ghost"
            size="sm"
            :disabled="pagination.page >= totalPages"
            :aria-label="$t('localization.index.next_page')"
            @click="changePage(pagination.page + 1)"
          >
            <ChevronRight class="size-4" />
          </Button>
        </div>
      </section>

      <section
        v-if="selectedText"
        class="min-w-0 overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm"
        :aria-label="$t('localization.index.translation_editor')"
      >
        <header class="flex items-center gap-3 border-b border-base-300 px-4 py-3">
          <Button
            variant="ghost"
            size="icon-sm"
            class="lg:hidden"
            :aria-label="$t('localization.edit.back')"
            @click="closeEditor"
          >
            <ChevronLeft class="size-4" />
          </Button>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <h2 class="truncate font-semibold">{{ selectedText.localeName }}</h2>
              <span :class="['badge badge-sm', statusClasses[status] || 'badge-ghost']">
                {{ $t(`localization.index.status_${status}`) }}
              </span>
              <span v-if="selectedText.stale" class="badge badge-error badge-outline badge-sm">
                <AlertTriangle class="size-3" /> {{ $t("localization.index.stale") }}
              </span>
              <span v-if="!canEdit" class="badge badge-ghost badge-sm">
                <Lock class="size-3" /> {{ $t("localization.edit.read_only") }}
              </span>
            </div>
            <p class="mt-0.5 truncate text-xs text-base-content/50">
              {{ selectedText.sourceReference }}
            </p>
          </div>
          <div class="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon-sm"
              :disabled="!previousText"
              :aria-label="$t('localization.edit.previous')"
              @click="selectRelative('previous')"
            >
              <ChevronLeft class="size-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              :disabled="!nextText"
              :aria-label="$t('localization.edit.next')"
              @click="selectRelative('next')"
            >
              <ChevronRight class="size-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              class="hidden lg:inline-flex"
              :aria-label="$t('localization.edit.close')"
              @click="closeEditor"
            >
              <X class="size-4" />
            </Button>
          </div>
        </header>

        <div class="grid gap-5 p-4 xl:grid-cols-2 xl:p-5">
          <div class="min-w-0 space-y-3">
            <div class="flex items-center justify-between">
              <h3 class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/50">
                {{ $t("localization.edit.source") }}
              </h3>
              <span class="text-xs text-base-content/45">
                {{ $t("localization.edit.word_count", selectedText.wordCount) }}
              </span>
            </div>
            <div class="min-h-52 rounded-xl border border-base-300 bg-base-200/60 p-4">
              <div
                class="prose prose-sm max-w-none text-base-content dark:prose-invert [&_*]:text-inherit"
                v-html="selectedText.sourceHtml"
              />
            </div>
            <div
              v-if="selectedText.placeholders.length"
              class="flex flex-wrap items-center gap-1.5"
            >
              <span class="text-xs text-base-content/45">{{
                $t("localization.edit.placeholders")
              }}</span>
              <code
                v-for="placeholder in selectedText.placeholders"
                :key="placeholder"
                class="rounded-md bg-base-200 px-1.5 py-0.5 text-xs font-medium text-primary"
              >
                {{ placeholder }}
              </code>
            </div>
          </div>

          <div class="min-w-0 space-y-3">
            <div class="flex items-center justify-between gap-3">
              <label
                for="localization-translation-editor"
                class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/50"
              >
                {{ $t("localization.edit.translation_label", { locale: selectedText.localeName }) }}
              </label>
              <div class="flex items-center gap-1.5 text-xs" aria-live="polite">
                <LoaderCircle
                  v-if="saveState === 'saving'"
                  class="size-3.5 animate-spin text-primary"
                />
                <Check v-else-if="saveState === 'saved'" class="size-3.5 text-success" />
                <Clock3 v-else-if="saveState === 'dirty'" class="size-3.5 text-warning" />
                <AlertTriangle
                  v-else-if="saveState === 'error' || saveState === 'conflict'"
                  class="size-3.5 text-error"
                />
                <span class="text-base-content/50">
                  {{ $t(`localization.edit.save_${saveState}`) }}
                </span>
              </div>
            </div>

            <Textarea
              id="localization-translation-editor"
              v-model="translatedText"
              class="min-h-52 resize-y text-[15px] leading-relaxed"
              :disabled="!canEdit"
              :placeholder="$t('localization.edit.translation_placeholder')"
              @keydown="onEditorKeydown"
            />

            <div v-if="placeholderIssue" class="alert alert-error py-2 text-sm" role="alert">
              <AlertTriangle class="size-4" />
              <span>
                {{ $t("localization.edit.placeholder_error") }}
                <code
                  v-for="item in placeholderIssue.missing"
                  :key="`missing-${item}`"
                  class="ml-1"
                  >{{ item }}</code
                >
              </span>
            </div>

            <div
              v-if="saveState === 'conflict'"
              class="alert alert-warning items-start py-3 text-sm"
              role="alert"
            >
              <AlertTriangle class="mt-0.5 size-4" />
              <div class="min-w-0 flex-1">
                <p class="font-medium">{{ $t("localization.edit.conflict_title") }}</p>
                <p class="mt-0.5 text-xs opacity-75">
                  {{ $t("localization.edit.conflict_description") }}
                </p>
                <div class="mt-2 flex gap-2">
                  <button type="button" class="btn btn-warning btn-xs" @click="retryAfterConflict">
                    {{ $t("localization.edit.overwrite") }}
                  </button>
                  <button type="button" class="btn btn-ghost btn-xs" @click="reloadAfterConflict">
                    {{ $t("localization.edit.reload") }}
                  </button>
                </div>
              </div>
            </div>

            <p v-if="saveState === 'error' && saveError" class="text-xs text-error" role="alert">
              {{ saveError }}
            </p>

            <div
              :class="[
                'grid gap-3',
                selectedText.sourceType === 'flow_node' ? 'sm:grid-cols-3' : 'sm:grid-cols-2',
              ]"
            >
              <div class="space-y-1.5">
                <label class="text-xs font-medium text-base-content/60">{{
                  $t("localization.edit.status")
                }}</label>
                <Select v-model="status" :disabled="!canEdit">
                  <SelectTrigger class="w-full">
                    <SelectValue :placeholder="$t('localization.edit.select_status')" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem
                      v-for="option in statusOptions"
                      :key="option.key"
                      :value="option.key"
                      :disabled="option.key === 'final' && finalUnavailable"
                    >
                      {{ $t(option.label) }}
                    </SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div v-if="selectedText.sourceType === 'flow_node'" class="space-y-1.5">
                <label class="text-xs font-medium text-base-content/60">{{
                  $t("localization.edit.vo_status")
                }}</label>
                <Select v-model="voStatus" :disabled="!canEdit">
                  <SelectTrigger class="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem
                      v-for="option in voStatusOptions"
                      :key="option.key"
                      :value="option.key"
                    >
                      {{ $t(option.label) }}
                    </SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div class="space-y-1.5">
                <label
                  for="localization-translator-notes"
                  class="text-xs font-medium text-base-content/60"
                >
                  {{ $t("localization.edit.translator_notes") }}
                </label>
                <Textarea
                  id="localization-translator-notes"
                  v-model="translatorNotes"
                  class="min-h-10 resize-y"
                  :disabled="!canEdit"
                  :placeholder="$t('localization.edit.notes_placeholder')"
                />
              </div>
            </div>

            <div
              v-if="canEdit"
              class="flex flex-wrap items-center gap-2 border-t border-base-300 pt-3"
            >
              <Button
                :disabled="saveState === 'saving' || !!placeholderIssue"
                @click="saveTranslation(false)"
              >
                {{ $t("localization.edit.save") }}
              </Button>
              <Button
                variant="outline"
                :disabled="saveState === 'saving' || !nextText || !!placeholderIssue"
                @click="saveTranslation(true)"
              >
                {{ $t("localization.edit.save_next") }}
                <ChevronRight class="size-4" />
              </Button>
              <Button
                v-if="hasProvider"
                variant="outline"
                :disabled="translating || saveState === 'saving'"
                @click="translateSingle(selectedText.id)"
              >
                <LoaderCircle v-if="translating" class="size-4 animate-spin" />
                <Sparkles v-else class="size-4" />
                {{ $t("localization.edit.translate_deepl") }}
              </Button>
              <span class="ml-auto hidden text-[11px] text-base-content/40 sm:inline">
                {{ $t("localization.edit.shortcut_hint") }}
              </span>
            </div>
          </div>
        </div>
      </section>

      <section
        v-else
        class="hidden min-h-96 items-center justify-center rounded-xl border border-dashed border-base-300 bg-base-100/60 p-10 text-center lg:flex"
      >
        <div class="max-w-xs">
          <Globe class="mx-auto size-10 text-base-content/20" />
          <h2 class="mt-4 font-semibold">{{ $t("localization.index.select_string") }}</h2>
          <p class="mt-1 text-sm text-base-content/50">
            {{ $t("localization.index.select_string_description") }}
          </p>
        </div>
      </section>
    </div>
  </DashboardContent>
</template>
